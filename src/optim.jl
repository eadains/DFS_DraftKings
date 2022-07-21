using JuMP
using Xpress
using Distributions
include("types.jl")


"""
    do_optim(data::MLBSlate)

Runs optimization for cash games
"""
function do_optim(slate::MLBSlate)
    model = Model(Xpress.Optimizer)

    p = length(slate.players)
    # Players variable
    @variable(model, x[1:p], binary = true)
    # Games variable
    @variable(model, g[slate.games], binary = true)

    # Total salary must be <= $50,000
    @constraint(model, sum(slate.players[i].Salary * x[i] for i = 1:p) <= 50000)
    # Must select 10 total players
    @constraint(model, sum(x) == 10)
    # Constraints for each position
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "P") == 2)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "C") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "1B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "2B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "3B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "SS") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "OF") == 3)

    for team in slate.teams
        # Maximum of 5 batters from each team
        @constraint(model, sum(x[i] for i = 1:p if (slate.players[i].Position != "P") && (slate.players[i].Team == team)) <= 5)
    end

    for game in slate.games
        # If no players are selected from a game z is set to 0
        @constraint(model, g[game] <= sum(x[i] for i = 1:p if slate.players[i].Game == game))
    end
    # Must select players from at least 2 games
    @constraint(model, sum(g) >= 2)

    # Maximize projected fantasy points
    @objective(model, Max, sum(slate.players[i].Projection * x[i] for i = 1:p))

    optimize!(model)
    println(termination_status(model))
    return (objective_value(model), round.(Int, value.(x)))
end


"""
    do_optim(data::MLBTournyOptimData)

Runs optimization for tournaments
"""
function do_optim(slate::MLBSlate, λ::Real, overlap::Integer, past_lineups::AbstractVector{<:AbstractVector{<:Integer}}, opp_mu::Real, opp_var::Real, opp_cov::AbstractVector{<:Real})
    model = Model(Xpress.Optimizer)

    p = length(slate.players)
    # Players variable
    @variable(model, x[1:p], binary = true)
    # Games variable
    @variable(model, g[slate.games], binary = true)

    # Total salary must be <= $50,000
    @constraint(model, sum(slate.players[i].Salary * x[i] for i = 1:p) <= 50000)
    # Must select 10 total players
    @constraint(model, sum(x) == 10)
    # Constraints for each position
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "P") == 2)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "C") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "1B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "2B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "3B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "SS") == 1)
    @constraint(model, sum(x[i] for i = 1:p if slate.players[i].Position == "OF") == 3)

    for team in slate.teams
        # Maximum of 5 batters from each team
        @constraint(model, sum(x[i] for i = 1:p if (slate.players[i].Position != "P") && (slate.players[i].Team == team)) <= 5)
    end

    for game in slate.games
        # If no players are selected from a game z is set to 0
        @constraint(model, g[game] <= sum(x[i] for i = 1:p if slate.players[i].Game == game))
    end
    # Must select players from at least 2 games
    @constraint(model, sum(g) >= 2)

    # If there are any past lineups, ensure that the current lineup doesn't overlap too much with any of them
    for past in past_lineups
        @constraint(model, sum(x[i] * past[i] for i = 1:p) <= overlap)
    end

    mu_x = @expression(model, x' * slate.μ - opp_mu)
    var_x = @expression(model, x' * slate.Σ * x + opp_var - 2 * x' * opp_cov)
    # Maximize projected fantasy points
    @objective(model, Max, mu_x + λ * var_x)

    optimize!(model)
    println(termination_status(model))
    # Return optimization result vector, as well as estimated probability of exceeding 220 points
    return (round.(Int, value.(x)), 1 - cdf(Normal(), -value(mu_x) / sqrt(value(var_x))))
end


"""
    lambda_max(data::MLBTournyOptimData)

Does optimization over range of λ values and returns the lineup with the highest objective function.
"""
function lambda_max(data::MLBSlate, past_lineups::AbstractVector{<:AbstractVector{<:Integer}}, overlap::Integer, opp_mu::Real, opp_var::Real, opp_cov::AbstractVector{<:Real})
    # I've found that lambdas from around 0 to 0.05 are selected, with most being 0.03
    lambdas = 0.01:0.01:0.10
    w_star = Vector{Tuple{Vector{Int64},Float64}}(undef, length(lambdas))
    # Perform optimization over array of λ values
    Threads.@threads for i in 1:length(lambdas)
        w_star[i] = do_optim(data, lambdas[i], overlap, past_lineups, opp_mu, opp_var, opp_cov)
    end

    # Find lambda value that leads to highest objective function and return its corresponding lineup vector
    max_index = argmax(x[2] for x in w_star)
    println("λ max: $(lambdas[max_index])")
    return w_star[max_index][1]
end


"""
    get_lineups(N::Integer)

Solves the tournament optimization problem with N entries.
Appends lineups to OptimData pastlineups array
"""
function tourny_lineups(data::MLBSlate, N::Integer, overlap::Integer, opp_mu::Real, opp_var::Real, opp_cov::AbstractVector{<:Real})
    past_lineups = Vector{Int64}[]
    for n in 1:N
        println(n)
        lineup = lambda_max(data, past_lineups, overlap, opp_mu, opp_var, opp_cov)
        append!(past_lineups, Ref(lineup))
    end
    return past_lineups
end
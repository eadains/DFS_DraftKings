using JuMP
using Xpress
using Distributions
include("types.jl")
include("payoffs.jl")


"""
    do_optim(data::MLBTournyOptimData)

Runs optimization for tournaments
"""
function do_optim(data::MLBTournyOptimData, λ::Real, past_lineups::AbstractVector{<:AbstractVector{<:Integer}})
    model = Model(Xpress.Optimizer)

    p = length(data.slate.players)
    # Players variable
    @variable(model, x[1:p], binary = true)
    # Games variable
    @variable(model, g[data.slate.games], binary = true)

    # Total salary must be <= $50,000
    @constraint(model, sum(data.slate.players[i].Salary * x[i] for i = 1:p) <= 50000)
    # Must select 10 total players
    @constraint(model, sum(x) == 10)
    # Constraints for each position
    @constraint(model, sum(x[i] for i = 1:p if data.slate.players[i].Position == "P") == 2)
    @constraint(model, sum(x[i] for i = 1:p if data.slate.players[i].Position == "C") == 1)
    @constraint(model, sum(x[i] for i = 1:p if data.slate.players[i].Position == "1B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if data.slate.players[i].Position == "2B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if data.slate.players[i].Position == "3B") == 1)
    @constraint(model, sum(x[i] for i = 1:p if data.slate.players[i].Position == "SS") == 1)
    @constraint(model, sum(x[i] for i = 1:p if data.slate.players[i].Position == "OF") == 3)

    for team in data.slate.teams
        # Maximum of 5 batters from each team
        @constraint(model, sum(x[i] for i = 1:p if (data.slate.players[i].Position != "P") && (data.slate.players[i].Team == team)) <= 5)
    end

    for game in data.slate.games
        # If no players are selected from a game z is set to 0
        @constraint(model, g[game] <= sum(x[i] for i = 1:p if data.slate.players[i].Game == game))
    end
    # Must select players from at least 2 games
    @constraint(model, sum(g) >= 2)

    # If there are any past lineups, ensure that the current lineup doesn't overlap too much with any of them
    for past in past_lineups
        @constraint(model, sum(x[i] * past[i] for i = 1:p) <= data.overlap)
    end

    mu_x = @expression(model, x' * data.slate.μ)
    #var_x = @expression(model, x' * data.slate.Σ * x - 2 * x' * data.opp_cov)
    var_x = @expression(model, x' * data.slate.Σ * x)
    # Maximize projected fantasy points
    @objective(model, Max, mu_x + λ * var_x)

    optimize!(model)
    println(termination_status(model))
    # Return optimization result vector, as well as estimated probability of exceeding 200 points
    # This is the average first place score for MLB contests on DraftKings
    #return (round.(Int, value.(x)), payoff(value(mu_x), value(var_x), data.order_stats_mu, data.order_stats_sigma, data.payoffs))
    return (round.(Int, value.(x)), 1 - cdf(Normal(), (200 - value(mu_x)) / sqrt(value(var_x))))
end


"""
    do_optim(data::PGATournyOptimData)

Runs optimization for tournaments
"""
function do_optim(data::PGATournyOptimData, λ::Real, past_lineups::AbstractVector{<:AbstractVector{<:Integer}})
    model = Model(Xpress.Optimizer)

    p = length(data.slate.players)
    # Players variable
    @variable(model, x[1:p], binary = true)

    # Total salary must be <= $50,000
    @constraint(model, sum(data.slate.players[i].Salary * x[i] for i = 1:p) <= 50000)
    # Must select 6 total players
    @constraint(model, sum(x) == 6)

    # If there are any past lineups, ensure that the current lineup doesn't overlap too much with any of them
    for past in past_lineups
        @constraint(model, sum(x[i] * past[i] for i = 1:p) <= data.overlap)
    end

    mu_x = @expression(model, x' * data.slate.μ)
    var_x = @expression(model, x' * data.slate.Σ * x - 2 * x' * data.opp_cov)
    # Maximize projected fantasy points
    @objective(model, Max, mu_x + λ * var_x)

    optimize!(model)
    println(termination_status(model))
    # Return optimization result vector, as well as expected payoff of the entry
    lineup = round.(Int, value.(x))
    return (lineup, get_expected_payoff(lineup, past_lineups, data))
end


"""
    lambda_max(data::TournyOptimData, past_lineups::AbstractVector{<:AbstractVector{<:Integer}})

Does optimization over range of λ values and returns the lineup with the highest objective function.
"""
function lambda_max(data::TournyOptimData, past_lineups::AbstractVector{<:AbstractVector{<:Integer}})
    # I've found that lambdas from around 0 to 0.05 are selected, with most being 0.03
    lambdas = 0.01:0.01:0.10
    w_star = Vector{Tuple{Vector{Int64},Float64}}(undef, length(lambdas))
    # Perform optimization over array of λ values
    Threads.@threads for i in 1:length(lambdas)
        w_star[i] = do_optim(data, lambdas[i], past_lineups)
    end

    # Find lambda value that leads to highest objective function and return its corresponding lineup vector
    max_index = argmax(x[2] for x in w_star)
    println("λ max: $(lambdas[max_index])")
    println("Expected Payoff: $(w_star[max_index][2])")
    return w_star[max_index][1]
end


"""
    tourny_lineups(data::TournyOptimData, N::Integer)

Solves the tournament optimization problem with N entries.
Appends lineups to OptimData pastlineups array
"""
function tourny_lineups(data::TournyOptimData, N::Integer)
    past_lineups = Vector{Int64}[]
    for n in 1:N
        println(n)
        lineup = lambda_max(data, past_lineups)
        append!(past_lineups, Ref(lineup))
    end
    return past_lineups
end
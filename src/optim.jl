using JuMP
using CPLEX
using Distributions
include("types.jl")


"""
    do_optim(data::MLBSlate)

Runs optimization for cash games
"""
function do_optim(slate::MLBSlate)
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPXPARAM_ScreenOutput", 0)

    # Players variable
    @variable(model, x[[player.ID for player in slate.players]], binary = true)
    # Games variable
    @variable(model, g[slate.games], binary = true)

    # Total salary must be <= $50,000
    @constraint(model, sum(player.Salary * x[player.ID] for player in slate.players) <= 50000)
    # Must select 10 total players
    @constraint(model, sum(x) == 10)
    # Constraints for each position
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "P") == 2)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "C") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "1B") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "2B") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "3B") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "SS") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "OF") == 3)

    for team in slate.teams
        # Maximum of 5 batters from each team
        @constraint(model, sum(x[player.ID] for player in slate.players if (player.Position != "P") && (player.Team == team)) <= 5)
    end

    for game in slate.games
        # If no players are selected from a game z is set to 0
        @constraint(model, g[game] <= sum(x[player.ID] for player in slate.players if player.Game == game))
    end
    # Must select players from at least 2 games
    @constraint(model, sum(g) >= 2)

    # Maximize projected fantasy points
    @objective(model, Max, sum(player.Projection * x[player.ID] for player in slate.players))

    optimize!(model)
    println(termination_status(model))
    return (objective_value(model), round.(Int, value.(x)))
end


"""
    do_optim(data::MLBTournyOptimData)

Runs optimization for tournaments
"""
function do_optim(slate::MLBSlate, λ::Float64, overlap::Integer, past_lineups::Vector{JuMP.Containers.DenseAxisArray})
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPXPARAM_ScreenOutput", 0)

    # Players variable
    @variable(model, x[[player.ID for player in slate.players]], binary = true)
    # Games variable
    @variable(model, g[slate.games], binary = true)

    # Total salary must be <= $50,000
    @constraint(model, sum(player.Salary * x[player.ID] for player in slate.players) <= 50000)
    # Must select 10 total players
    @constraint(model, sum(x) == 10)
    # Constraints for each position
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "P") == 2)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "C") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "1B") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "2B") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "3B") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "SS") == 1)
    @constraint(model, sum(x[player.ID] for player in slate.players if player.Position == "OF") == 3)

    for team in slate.teams
        # Maximum of 5 batters from each team
        @constraint(model, sum(x[player.ID] for player in slate.players if (player.Position != "P") && (player.Team == team)) <= 5)
    end

    for game in slate.games
        # If no players are selected from a game z is set to 0
        @constraint(model, g[game] <= sum(x[player.ID] for player in slate.players if player.Game == game))
    end
    # Must select players from at least 2 games
    @constraint(model, sum(g) >= 2)

    # If there are any past lineups, ensure that the current lineup doesn't overlap too much with any of them
    if length(past_lineups) > 0
        for past in past_lineups
            @constraint(model, sum(x[player.ID] * past[player.ID] for player in slate.players) <= overlap)
        end
    end

    mu_x = @expression(model, x.data' * slate.μ)
    var_x = @expression(model, x.data' * slate.Σ * x.data)
    # Maximize projected fantasy points
    @objective(model, Max, mu_x + λ * var_x)

    optimize!(model)
    println(termination_status(model))
    # Return optimization result vector, as well as estimated probability of exceeding 250 points
    return (round.(Int, value.(x)), 1 - cdf(Normal(), (250 - value(mu_x)) / sqrt(value(var_x))))
end


"""
    lambda_max(data::MLBTournyOptimData)

Does optimization over range of λ values and returns the lineup with the highest objective function.
"""
function lambda_max(data::MLBSlate, past_lineups::Vector{JuMP.Containers.DenseAxisArray}, overlap::Integer)
    # I've found that lambdas from around 0 to 0.05 are selected, with most being 0.03
    lambdas = 0.01:0.01:0.10
    w_star = Vector{Tuple{JuMP.Containers.DenseAxisArray,Float64}}(undef, length(lambdas))
    # Perform optimization over array of λ values
    Threads.@threads for i in 1:length(lambdas)
        w_star[i] = do_optim(data, lambdas[i], overlap, past_lineups)
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
function tourny_lineups(data::MLBSlate, N::Integer, overlap::Integer)
    past_lineups = JuMP.Containers.DenseAxisArray[]
    for n in 1:N
        println(n)
        lineup = lambda_max(data, past_lineups, overlap)
        append!(past_lineups, Ref(lineup))
    end
    return past_lineups
end
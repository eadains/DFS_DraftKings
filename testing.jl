include("./src/solve.jl")
using CPLEX
using SCIP
using Distributions

function find_thetasq_upper_bound(slate)
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPXPARAM_ScreenOutput", 0)
    set_optimizer_attribute(model, "CPXPARAM_Emphasis_MIP", 5)
    set_optimizer_attribute(model, "CPXPARAM_TimeLimit", 180)

    p = length(slate.players)
    # Players variable
    @variable(model, x[1:2, 1:p], binary = true)
    # Games variable
    @variable(model, g[slate.games], binary = true)
    # Linearization variables
    @variable(model, v[1:2, 1:p, 1:p], binary = true)
    @variable(model, r[1:p, 1:p], binary = true)

    for j in 1:2
        # Total salary must be <= $50,000
        @constraint(model, sum(slate.players[i].Salary * x[j, i] for i = 1:p) <= 50000)
        # Must select 10 total players
        @constraint(model, sum(x[j, :]) == 10)
        # Constraints for each position
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "P") == 2)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "C") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "1B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "2B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "3B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "SS") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "OF") == 3)

        for team in slate.teams
            # Maximum of 5 batters from each team
            @constraint(model, sum(x[j, i] for i = 1:p if (slate.players[i].Position != "P") && (slate.players[i].Team == team)) <= 5)
        end

        for game in slate.games
            # If no players are selected from a game z is set to 0
            @constraint(model, g[game] <= sum(x[j, i] for i = 1:p if slate.players[i].Game == game))
        end
        # Must select players from at least 2 games
        @constraint(model, sum(g) >= 2)
    end

    # Expectation of team 1 and 2
    u_1 = @expression(model, sum(x[1, i] * slate.μ[i] for i = 1:p))
    u_2 = @expression(model, sum(x[2, i] * slate.μ[i] for i = 1:p))
    # Symmetry breaking condition
    @constraint(model, u_1 >= u_2)

    s = @expression(model, sum(sum(slate.Σ[j, j] * x[i, j] for j in 1:p) + 2 * sum(slate.Σ[j_1, j_2] * v[i, j_1, j_2] for j_1 = 1:p, j_2 = 1:p if j_1 < j_2) for i in 1:2) - 2 * sum(sum(slate.Σ[j_1, j_2] * r[j_1, j_2] for j_2 in 1:p) for j_1 in 1:p))
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] <= x[i, j_1])
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] <= x[i, j_2])
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] >= x[i, j_1] + x[i, j_2] - 1)
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] <= x[1, j_1])
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] <= x[2, j_2])
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] >= x[1, j_1] + x[2, j_2] - 1)

    @objective(model, Max, s)
    optimize!(model)
    return value(s)
end


function make_thetasq_intervals(upper_bound, n)
    intervals = Vector{Float64}(undef, n + 1)
    intervals[1] = 0
    intervals[2] = 1
    for i in 3:n+1
        intervals[i] = intervals[i-1] + (upper_bound - 1) / (n - 1)
    end
    return intervals
end


function find_delta_upper_bound(slate)
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPXPARAM_ScreenOutput", 0)
    set_optimizer_attribute(model, "CPXPARAM_Emphasis_MIP", 5)
    set_optimizer_attribute(model, "CPXPARAM_TimeLimit", 180)

    p = length(slate.players)
    @variable(model, x[1:2, 1:p], binary = true)
    # Games variable
    @variable(model, g[slate.games], binary = true)
    # Linearization variables
    @variable(model, v[1:2, 1:p, 1:p], binary = true)
    @variable(model, r[1:p, 1:p], binary = true)

    for j in 1:2
        # Total salary must be <= $50,000
        @constraint(model, sum(slate.players[i].Salary * x[j, i] for i = 1:p) <= 50000)
        # Must select 10 total players
        @constraint(model, sum(x[j, :]) == 10)
        # Constraints for each position
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "P") == 2)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "C") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "1B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "2B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "3B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "SS") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "OF") == 3)

        for team in slate.teams
            # Maximum of 5 batters from each team
            @constraint(model, sum(x[j, i] for i = 1:p if (slate.players[i].Position != "P") && (slate.players[i].Team == team)) <= 5)
        end

        for game in slate.games
            # If no players are selected from a game z is set to 0
            @constraint(model, g[game] <= sum(x[j, i] for i = 1:p if slate.players[i].Game == game))
        end
        # Must select players from at least 2 games
        @constraint(model, sum(g) >= 2)
    end

    # Expectation of team 1 and 2
    u_1 = @expression(model, sum(x[1, i] * slate.μ[i] for i = 1:p))
    u_2 = @expression(model, sum(x[2, i] * slate.μ[i] for i = 1:p))
    # Symmetry breaking condition
    @constraint(model, u_1 >= u_2)

    s = @expression(model, sum(sum(slate.Σ[j, j] * x[i, j] for j in 1:p) + 2 * sum(slate.Σ[j_1, j_2] * v[i, j_1, j_2] for j_1 = 1:p, j_2 = 1:p if j_1 < j_2) for i in 1:2) - 2 * sum(sum(slate.Σ[j_1, j_2] * r[j_1, j_2] for j_2 in 1:p) for j_1 in 1:p))
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] <= x[i, j_1])
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] <= x[i, j_2])
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] >= x[i, j_1] + x[i, j_2] - 1)
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] <= x[1, j_1])
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] <= x[2, j_2])
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] >= x[1, j_1] + x[2, j_2] - 1)

    delta = @expression(model, u_1 - u_2)

    @objective(model, Max, delta)
    optimize!(model)
    return value(delta)
end


function make_delta_intervals(upper_bound, n)
    intervals = Vector{Float64}(undef, n + 1)
    for i in 1:n+1
        intervals[i] = ((i - 1) / n) * upper_bound
    end
    return intervals
end


function make_theta_upper_intervals(thetasq_intervals)
    theta_upper_intervals = Vector{Float64}(undef, length(thetasq_intervals) - 1)
    for i in 1:length(theta_upper_intervals)
        if i == 1
            theta_upper_intervals[i] = 1
        else
            theta_upper_intervals[i] = sqrt(thetasq_intervals[i+1])
        end
    end
    return theta_upper_intervals
end


function make_theta_lower_intervals(thetasq_intervals)
    theta_lower_intervals = Vector{Float64}(undef, length(thetasq_intervals) - 1)
    for i in 1:length(theta_lower_intervals)
        if i == 1
            theta_lower_intervals[i] = 0
        else
            theta_lower_intervals[i] = sqrt(thetasq_intervals[i])
        end
    end
    return theta_lower_intervals
end


function make_cdf_constants(theta_lower_intervals, delta_intervals)
    d = length(theta_lower_intervals)
    l = length(delta_intervals) - 1
    cdf_constants = Matrix{Float64}(undef, d, l)
    for q in 1:d
        for k in 1:l
            cdf_constants[q, k] = cdf(Normal(), delta_intervals[k+1] / theta_lower_intervals[q])
        end
    end
    return cdf_constants
end


function find_u_max(slate)
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPXPARAM_ScreenOutput", 0)
    set_optimizer_attribute(model, "CPXPARAM_TimeLimit", 180)

    p = length(slate.players)
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

    obj = @expression(model, sum(x[i] * slate.μ[i] for i = 1:p))
    @objective(model, Max, obj)
    optimize!(model)
    return value(obj)
end


function find_z(slate)
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPXPARAM_ScreenOutput", 0)
    set_optimizer_attribute(model, "CPXPARAM_TimeLimit", 180)

    p = length(slate.players)
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

    mu = @expression(model, sum(x[i] * slate.μ[i] for i = 1:p))
    var = @expression(model, x' * slate.Σ * x)

    @objective(model, Min, mu + var)
    optimize!(model)
    return value(mu)
end


function LBP(delta, u_max, z)
    model = Model(() -> SCIP.Optimizer(display_verblevel=0))
    @variable(model, theta)

    @constraint(model, theta >= 0)
    @NLconstraint(model, u_max + theta * ((1 / sqrt(2pi)) * exp((delta / theta)^2 / 2)) >= z)

    @objective(model, Min, theta)
    optimize!(model)
    return value(theta)
end


function make_SVIs(delta_intervals, u_max, z)
    l = length(delta_intervals) - 1
    SVIs = Vector{Float64}(undef, l)
    Threads.@threads for i in 1:l
        SVIs[i] = LBP(delta_intervals[i], u_max, z)
    end
    return SVIs
end


struct OptimConstants
    thetasq_intervals::AbstractVector{<:Real}
    theta_upper_intervals::AbstractVector{<:Real}
    delta_intervals::AbstractVector{<:Real}
    cdf_constants::AbstractMatrix{<:Real}
    SVIs::AbstractVector{<:Real}
end

function make_optim_constants(slate::MLBSlate)
    println("Theta Square Upper Bound")
    thetasq_upper_bound = find_thetasq_upper_bound(slate)
    thetasq_intervals = make_thetasq_intervals(thetasq_upper_bound, 50)
    theta_upper_intervals = make_theta_upper_intervals(thetasq_intervals)
    theta_lower_intervals = make_theta_lower_intervals(thetasq_intervals)
    println("Delta upper bound")
    delta_upper_bound = find_delta_upper_bound(slate)
    delta_intervals = make_delta_intervals(delta_upper_bound, 50)
    cdf_constants = make_cdf_constants(theta_lower_intervals, delta_intervals)
    println("U Max")
    u_max = find_u_max(slate)
    println("Z")
    z = find_z(slate)
    println("SVIs")
    SVIs = make_SVIs(delta_intervals, u_max, z)
    return OptimConstants(thetasq_intervals, theta_upper_intervals, delta_intervals, cdf_constants, SVIs)
end


function do_sd_optim(constants::OptimConstants, slate::MLBSlate)
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPXPARAM_MIP_Display", 4)
    set_optimizer_attribute(model, "CPXPARAM_Emphasis_MIP", 5)
    set_optimizer_attribute(model, "CPXPARAM_TimeLimit", 1200)

    p = length(slate.players)
    @variable(model, x[1:2, 1:p], binary = true)
    # Games variable
    @variable(model, g[slate.games], binary = true)
    # Linearization variables
    @variable(model, v[1:2, 1:p, 1:p], binary = true)
    @variable(model, r[1:p, 1:p], binary = true)
    # Interval selection variables
    @variable(model, w[1:50], binary = true)
    @variable(model, y[1:50], binary = true)
    @variable(model, u_prime)

    for j in 1:2
        # Total salary must be <= $50,000
        @constraint(model, sum(slate.players[i].Salary * x[j, i] for i = 1:p) <= 50000)
        # Must select 10 total players
        @constraint(model, sum(x[j, :]) == 10)
        # Constraints for each position
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "P") == 2)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "C") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "1B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "2B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "3B") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "SS") == 1)
        @constraint(model, sum(x[j, i] for i = 1:p if slate.players[i].Position == "OF") == 3)

        for team in slate.teams
            # Maximum of 5 batters from each team
            @constraint(model, sum(x[j, i] for i = 1:p if (slate.players[i].Position != "P") && (slate.players[i].Team == team)) <= 5)
        end

        for game in slate.games
            # If no players are selected from a game z is set to 0
            @constraint(model, g[game] <= sum(x[j, i] for i = 1:p if slate.players[i].Game == game))
        end
        # Must select players from at least 2 games
        @constraint(model, sum(g) >= 2)
    end

    # Expectation of team 1 and 2
    u_1 = @expression(model, sum(x[1, i] * slate.μ[i] for i = 1:p))
    u_2 = @expression(model, sum(x[2, i] * slate.μ[i] for i = 1:p))
    # Symmetry breaking condition
    @constraint(model, u_1 >= u_2)

    s = @expression(model, sum(sum(slate.Σ[j, j] * x[i, j] for j in 1:p) + 2 * sum(slate.Σ[j_1, j_2] * v[i, j_1, j_2] for j_1 = 1:p, j_2 = 1:p if j_1 < j_2) for i in 1:2) - 2 * sum(sum(slate.Σ[j_1, j_2] * r[j_1, j_2] for j_2 in 1:p) for j_1 in 1:p))
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] <= x[i, j_1])
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] <= x[i, j_2])
    @constraint(model, [i = 1:2, j_1 = 1:p, j_2 = 1:p], v[i, j_1, j_2] >= x[i, j_1] + x[i, j_2] - 1)
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] <= x[1, j_1])
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] <= x[2, j_2])
    @constraint(model, [j_1 = 1:p, j_2 = 1:p], r[j_1, j_2] >= x[1, j_1] + x[2, j_2] - 1)

    @constraint(model, sum(w[i] for i = 1:50) == 1)
    @constraint(model, sum(y[i] for i = 1:50) == 1)

    @constraint(model, [q = 1:50], constants.thetasq_intervals[q] * w[q] <= s)
    @constraint(model, [q = 1:50], s <= constants.thetasq_intervals[q+1] + constants.thetasq_intervals[51] * (1 - w[q]))

    @constraint(model, [k = 1:50], constants.delta_intervals[k] * y[k] <= u_1 - u_2)
    @constraint(model, [k = 1:50], u_1 - u_2 <= constants.delta_intervals[k+1] + constants.delta_intervals[51] * (1 - y[k]))

    @constraint(model, [q = 1:50, k = 1:50], u_prime <= u_1 * constants.cdf_constants[q, k] + u_2 * (1 - constants.cdf_constants[q, k]) + 250 * (2 - w[q] - y[k]))

    @constraint(model, [k = 1:50], s >= constants.SVIs[k]^2 * y[k])

    s_prime = @expression(model, sum(constants.theta_upper_intervals[q] * w[q] for q = 1:50))

    @objective(model, Max, u_prime + (1 / sqrt(2pi)) * s_prime)
    optimize!(model)
    return round.(Int, value.(x))
end


function emax(x::AbstractMatrix{<:Integer}, slate::MLBSlate)
    mu_x1 = x[1, :]' * slate.μ
    mu_x2 = x[2, :]' * slate.μ
    var_x1 = x[1, :]' * slate.Σ * x[1, :]
    var_x2 = x[2, :]' * slate.Σ * x[2, :]
    cov = x[1, :]' * slate.Σ * x[2, :]

    theta = sqrt(var_x1 + var_x2 - 2 * cov)

    Φ = x -> cdf(Normal(), x)
    ϕ = x -> pdf(Normal(), x)

    return mu_x1 * Φ((mu_x1 - mu_x2) / theta) + mu_x2 * Φ((mu_x2 - mu_x1) / theta) + theta * ϕ((mu_x1 - mu_x2) / theta)
end


for i in 1:2
    lineup = transform_lineup(slate, lineups[i, :])
    println("$(lineup["P1"]),$(lineup["P2"]),$(lineup["C"]),$(lineup["1B"]),$(lineup["2B"]),$(lineup["3B"]),$(lineup["SS"]),$(lineup["OF1"]),$(lineup["OF2"]),$(lineup["OF3"])")
end
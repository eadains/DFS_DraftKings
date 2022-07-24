using Distributions
using StatsBase
using RandomNumbers.Xorshifts
using Memoize
include("types.jl")
rng = Xoroshiro128Plus()


"""
    find_players(slate::MLBSlate, position::String)

Given an MLB slate, find players with given position.
Returns integer indices of players found.
Memoize because of limited number of positions that get called repeatedly
"""
@memoize function find_players(slate::MLBSlate, position::AbstractString)
    indices = Int64[]
    for i in 1:length(slate.players)
        if slate.players[i].Position == position
            append!(indices, i)
        end
    end
    return indices
end


"""
    make_probs(slate::Slate, indices::AbstractVector{<:Integer})

Given a slate and a set of indices, calculates the normalized probabilities of selecting
those players specified by the indices.
Memoize because of repeated calls with same input parameters
"""
@memoize function make_probs(slate::Slate, indices::AbstractVector{<:Integer})
    nominal_weights = [x.pOwn for x in slate.players[indices]]
    return ProbabilityWeights(nominal_weights ./ sum(nominal_weights))
end


"""
    gen_team(slate::Slate)

Given a slate, generates a random opponent team using projected ownership numbers.
Not gauranteed to be a valid team.
"""
function gen_team(slate::Slate)
    team = Int16[]
    for position in keys(slate.positions)
        indices = find_players(slate, position)
        probs = make_probs(slate, indices)
        append!(team, sample(rng, indices, probs, slate.positions[position], replace=false))
    end
    return team
end


"""
    verify_team(slate::MLBSlate, indices::AbstractVector{<:Integer})

Given an MLB slate and indices representing players selected for a lineup, determine if those players
form a valid lineup
"""
function verify_team(slate::MLBSlate, indices::AbstractVector{<:Integer})
    team = slate.players[indices]
    # Count number of hitters per team
    teams_player_count = countmap([x.Team for x in team if x.Position != "P"])
    # Count number of games we've selected
    games_count = countmap([x.Game for x in team])
    constraints = [
        # Must select 10 players
        length(team) == 10,
        # Salary must be under 50000, but assume people use most of it
        48000 <= sum([x.Salary for x in team]) <= 50000,
        # Must select no more than 5 hitters per team
        all(values(teams_player_count) .<= 5),
        # Must select players from at least 2 games
        length(keys(games_count)) >= 2
    ]
    return all(constraints)
end


"""
    opp_team_score(slate::Slate, μ::AbstractVector{<:Real})

Computes the expected score of an opponent lineup given a slate and a vector of expected player scores.
Generates random teams until a valid one is selected, and returns the expected points.
"""
function opp_team_score(slate::Slate, μ::AbstractVector{<:Real})
    while true
        indices = gen_team(slate)
        if verify_team(slate, indices)
            return sum(μ[indices])
        end
    end
end


"""
    get_opp_scores(slate::Slate, μ::AbstractVector{<:Real}, entries::Integer)

Get sorted list of opponent lineup scores
"""
function get_opp_scores(slate::Slate, μ::AbstractVector{<:Real}, entries::Integer)
    opp_scores = Vector{Float64}(undef, entries)
    for i = 1:entries
        opp_scores[i] = opp_team_score(slate, μ)
    end
    sort!(opp_scores, rev=true)
    return opp_scores
end


"""
    get_samples(slate::Slate, entries::Integer, samples::Integer)

Get samples of random player score draws and opponent scores
"""
function get_samples(slate::Slate, entries::Integer, samples::Integer)
    score_draws = Vector{Vector{Float64}}(undef, samples)
    opp_scores = Vector{Vector{Float64}}(undef, samples)
    Threads.@threads for i in 1:samples
        draw = rand(MvNormal(slate.μ, slate.Σ))
        scores = get_opp_scores(slate, draw, entries)
        println("$(i) done.")
        score_draws[i] = draw
        opp_scores[i] = scores
    end
    return (score_draws, opp_scores)
end


"""
    get_order_stats(slate::Slate, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}}, entries::Integer, samples::Integer)

Get mean, variance, and covariance of order statistics given ranks defined in payoffs
"""
function get_order_stats(slate::Slate, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}}, entries::Integer, samples::Integer)
    score_draws, opp_scores = get_samples(slate, entries, samples)
    order_stats_mu = Dict{Int64,Float64}()
    order_stats_sigma = Dict{Int64,Float64}()
    opp_cov = Vector{Float64}()
    for (rank, payoff) in payoffs
        if payoff == 0
            # The rank 1 before the first rank where payoff is 0 is the last rank that gets paid
            r = rank - 1
            # Compute covariance between each players score draws and the rth order statistic of opponent scores
            opp_cov = [cov([x[i] for x in score_draws], [x[r] for x in opp_scores]) for i in 1:length(slate.players)]
        end
        # Get mean and variance of order statistics for each rank
        order_stats_mu[rank] = mean(x[rank] for x in opp_scores)
        order_stats_sigma[rank] = var(x[rank] for x in opp_scores)
    end
    return (order_stats_mu, order_stats_sigma, opp_cov)
end


"""
    payoff(lineup_mu::Real, lineup_var::Real, order_stats_mu::AbstractDict{<:Integer,<:Real}, order_stats_sigma::AbstractDict{<:Integer,<:Real}, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}})

Calculates expected payoff given a lineups mean and variance
"""
function payoff(lineup_mu::Real, lineup_var::Real, order_stats_mu::AbstractDict{<:Integer,<:Real}, order_stats_sigma::AbstractDict{<:Integer,<:Real}, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}})
    E = 0
    for i in 1:(length(payoffs)-1)
        mu = lineup_mu - order_stats_mu[payoffs[i][1]]
        sigmasq = lineup_var + order_stats_sigma[payoffs[i][1]]
        rank_payoff = (payoffs[i][2] - payoffs[i+1][2]) * (1 - cdf(Normal(), -mu / sqrt(sigmasq)))
        E += rank_payoff
    end
    return E
end
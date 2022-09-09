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
    gen_team(slate::MLBSlate)

Given a MLBslate, generates a random opponent team using projected ownership numbers.
Not gauranteed to be a valid team.
"""
function gen_team(slate::MLBSlate)
    team = Int16[]
    for position in keys(slate.positions)
        indices = find_players(slate, position)
        probs = make_probs(slate, indices)
        append!(team, sample(rng, indices, probs, slate.positions[position], replace=false))
    end
    return team
end


"""
    gen_team(slate::PGASlate)

Given a PGASlate, generates a random opponent team using projected ownership numbers.
Not gauranteed to be a valid team.
"""
function gen_team(slate::PGASlate)
    # There are no positions in Golf, so we just need to select 6 random players
    # from the entire slate of players
    indices = 1:length(slate.players)
    probs = make_probs(slate, indices)
    team = sample(rng, indices, probs, slate.positions["G"], replace=false)
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
        49000 <= sum([x.Salary for x in team]) <= 50000,
        # Must select no more than 5 hitters per team
        all(values(teams_player_count) .<= 5),
        # Must select players from at least 2 games
        length(keys(games_count)) >= 2
    ]
    return all(constraints)
end


"""
    verify_team(slate::PGASlate, indices::AbstractVector{<:Integer})

Given a PGA slate and indices representing players selected for a lineup, determine if those players
form a valid lineup
"""
function verify_team(slate::PGASlate, indices::AbstractVector{<:Integer})
    team = slate.players[indices]
    constraints = [
        # Must select 6 golfers
        length(team) == 6,
        # Salary must be under 50000, but assume people use most of it
        48000 <= sum([x.Salary for x in team]) <= 50000
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


function get_opp_cov(score_draws, opp_scores)
    # Number of players
    n = length(score_draws[1])
    # Following the paper, we assume covariance dependence on ranking is low
    # so just use the 10th percentile rank
    d = round(Int, 0.10 * length(opp_scores[1]))
    return [cov([x[i] for x in score_draws], [x[d] for x in opp_scores]) for i = 1:n]
end
using Distributions
using StatsBase
using RandomNumbers.Xorshifts
using Memoize
include("types.jl")
rng = Xoroshiro128Plus()


"""
    find_players(slate::Slate, position::String)

Given a slate, find players with given position.
Returns integer indices of players found.
Memoize because of limited number of positions that get called repeatedly
"""
@memoize function find_players(slate::Slate, position::AbstractString)
    indices = Int64[]
    for i in 1:length(slate.players)
        if slate.players[i].Position == position
            append!(indices, i)
        end
    end
    return indices
end


"""
    find_players(slate::Slate, position::String, team::AbstractString)

Given a slate, find players with given position and team.
Used for finding matching WR for a QB in NFL teams
Returns integer indices of players found.
Memoize because of limited number of positions that get called repeatedly
"""
@memoize function find_players(slate::Slate, position::AbstractString, team::AbstractString)
    indices = Int64[]
    for i in 1:length(slate.players)
        if (slate.players[i].Position == position) && (slate.players[i].Team == team)
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
    if all(nominal_weights .== 0)
        # If all projected ownerships are 0 assume equal probabilities
        nominal_weights = ones(length(indices))
    end
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
    gen_team(slate::NFLSlate)

Given a NFLSlate, generates a random opponent team using projected ownership numbers.
Not gauranteed to be a valid team.
"""
function gen_team!(team::AbstractVector{<:Integer}, slate::NFLSlate, gen_info::TeamGenInfo)
    i = 1
    for position in keys(slate.positions)
        if position == "QB"
            # Sample returns vector so select element
            QB = sample(rng, gen_info.pos_probs[position][1], gen_info.pos_probs[position][2], slate.positions[position], replace=false)[1]
            WR = sample(rng, gen_info.stack_probs[QB][1], gen_info.stack_probs[QB][2], 1, replace=false)
            team[i:i+1] = [QB; WR]
            i += 2
        elseif position == "WR"
            team[i:i+slate.positions[position]-2] = sample(rng, gen_info.pos_probs[position][1], gen_info.pos_probs[position][2], slate.positions[position] - 1, replace=false)
            i += slate.positions[position] - 1
        else
            team[i:i+slate.positions[position]-1] = sample(rng, gen_info.pos_probs[position][1], gen_info.pos_probs[position][2], slate.positions[position], replace=false)
            i += slate.positions[position]
        end
    end
    return team
end


function make_gen_info(slate::NFLSlate)
    pos_probs_dict = Dict{String,Tuple{Vector{Int},ProbabilityWeights}}()
    stacking_dict = Dict{Int,Tuple{Vector{Int},ProbabilityWeights}}()
    for position in keys(slate.positions)
        if position == "FLEX"
            indices = [find_players(slate, "RB"); find_players(slate, "WR"); find_players(slate, "TE")]
            probs = make_probs(slate, indices)
        else
            indices = find_players(slate, position)
            probs = make_probs(slate, indices)
        end
        pos_probs_dict[position] = (indices, probs)
    end

    for n in find_players(slate, "QB")
        matching_wrs = find_players(slate, "WR", slate.players[n].Team)
        stacking_dict[n] = (matching_wrs, make_probs(slate, matching_wrs))
    end
    return TeamGenInfo(pos_probs_dict, stacking_dict)
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
        45000 <= sum([x.Salary for x in team]) <= 50000,
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
        45000 <= sum([x.Salary for x in team]) <= 50000
    ]
    return all(constraints)
end


"""
    verify_team(slate::NFLSlate, indices::AbstractVector{<:Integer})

Given an NFL slate and indices representing players selected for a lineup, determine if those players
form a valid lineup
"""
function verify_team(slate::NFLSlate, indices::AbstractVector{<:Integer})
    team = slate.players[indices]
    # Count number of games we've selected
    games_count = countmap([x.Game for x in team])
    constraints = [
        # Salary must be under 50000, but assume people use most of it
        45000 <= sum([x.Salary for x in team]) <= 50000,
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
function opp_team_score(slate::Slate, μ::AbstractVector{<:Real}, gen_info::TeamGenInfo)
    team = Vector{Int}(undef, 9)
    while true
        gen_team!(team, slate, gen_info)
        if verify_team(slate, team)
            return sum(μ[team])
        end
    end
end


"""
    get_opp_scores(slate::Slate, μ::AbstractVector{<:Real}, entries::Integer)

Get sorted list of opponent lineup scores
"""
function get_opp_scores(slate::Slate, μ::AbstractVector{<:Real}, entries::Integer, gen_info::TeamGenInfo)
    opp_scores = Vector{Float64}(undef, entries)
    for i = 1:entries
        opp_scores[i] = opp_team_score(slate, μ, gen_info)
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
    gen_info = make_gen_info(slate)
    Threads.@threads for i in 1:samples
        draw = rand(MvNormal(slate.μ, slate.Σ))
        scores = get_opp_scores(slate, draw, entries, gen_info)
        sort!(scores, rev=true)
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
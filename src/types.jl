struct TeamGenInfo
    pos_probs::Dict{String,Tuple{Vector{Int},ProbabilityWeights}}
    stack_probs::Dict{Int,Tuple{Vector{Int},ProbabilityWeights}}
end


abstract type Slate end

struct MLBSlate <: Slate
    positions::Dict{String,Int}
    players::Vector{@NamedTuple{Name::String, ID::Int, Position::String, Salary::Int, Game::String, Team::String, Opponent::String, Order::Int, Projection::Float64, pOwn::Float64}}
    games::Vector{String}
    teams::Vector{String}
    μ::Vector{Float64}
    Σ::Matrix{Float64}
end


# Construct MLBSlate with DraftKings position numbers
function MLBSlate(players, games, teams, μ, Σ)
    positions = Dict(
        "P" => 2,
        "C" => 1,
        "1B" => 1,
        "2B" => 1,
        "3B" => 1,
        "SS" => 1,
        "OF" => 3
    )
    return MLBSlate(positions, players, games, teams, μ, Σ)
end


struct PGASlate <: Slate
    positions::Dict{String,Int}
    players::Vector{@NamedTuple{Name::String, ID::Int, Salary::Int, Projection::Float64, pOwn::Float64}}
    μ::Vector{Float64}
    Σ::Matrix{Float64}
end


function PGASlate(players, μ, Σ)
    positions = Dict(
        "G" => 6
    )
    return PGASlate(positions, players, μ, Σ)
end


struct NFLSlate <: Slate
    positions::Dict{String,Int}
    players::Vector{@NamedTuple{Name::String, ID::Int, Position::String, Salary::Int, Game::String, Team::String, Opponent::String, Projection::Float64, pOwn::Float64}}
    games::Vector{String}
    teams::Vector{String}
    μ::Vector{Float64}
    Σ::Matrix{Float64}
end


function NFLSlate(players, games, teams, μ, Σ)
    positions = Dict(
        "QB" => 1,
        "RB" => 2,
        "WR" => 3,
        "TE" => 1,
        "DST" => 1,
        "FLEX" => 1
    )
    return NFLSlate(positions, players, games, teams, μ, Σ)
end


abstract type TournyOptimData end


struct MLBTournyOptimData <: TournyOptimData
    slate::MLBSlate
    overlap::Int
    payoffs::Vector{Tuple{Int,Float64}}
    order_stats_mu::Dict{Int,Float64}
    order_stats_sigma::Dict{Int,Float64}
    opp_cov::Vector{Float64}
end


function MLBTournyOptimData(slate, payoffs, overlap, entries, samples)
    score_draws, opp_scores = get_samples(slate, entries, samples)
    opp_cov = get_opp_cov(score_draws, opp_scores)
    return MLBTournyOptimData(slate, overlap, payoffs, opp_cov, score_draws, opp_scores)
end


struct PGATournyOptimData <: TournyOptimData
    slate::PGASlate
    overlap::Integer
    payoffs::Vector{Tuple{Int,Float64}}
    opp_cov::Vector{Float64}
    score_draws::Vector{Vector{Float64}}
    opp_scores::Vector{Vector{Float64}}
end


function PGATournyOptimData(slate, payoffs, overlap, entries, samples)
    score_draws, opp_scores = get_samples(slate, entries, samples)
    opp_cov = get_opp_cov(score_draws, opp_scores)
    return PGATournyOptimData(slate, overlap, payoffs, opp_cov, score_draws, opp_scores)
end


struct NFLTournyOptimData <: TournyOptimData
    slate::NFLSlate
    overlap::Int
    payoffs::Vector{Tuple{Int,Float64}}
    opp_cov::Vector{Float64}
    score_draws::Vector{Vector{Float64}}
    opp_scores::Vector{Vector{Float64}}
end


function NFLTournyOptimData(slate, payoffs, overlap, entries, samples)
    score_draws, opp_scores = get_samples(slate, entries, samples)
    opp_cov = get_opp_cov(score_draws, opp_scores)
    return NFLTournyOptimData(slate, overlap, payoffs, opp_cov, score_draws, opp_scores)
end
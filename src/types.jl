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
    order_stats_mu, order_stats_sigma, opp_cov = get_order_stats(slate, payoffs, entries, samples)
    return MLBTournyOptimData(slate, overlap, payoffs, order_stats_mu, order_stats_sigma, opp_cov)
end


struct PGATournyOptimData <: TournyOptimData
    slate::PGASlate
    overlap::Integer
    payoffs::Vector{Tuple{Int,Float64}}
    order_stats_mu::Dict{Int,Float64}
    order_stats_sigma::Dict{Int,Float64}
    opp_cov::Vector{Float64}
end


function PGATournyOptimData(slate, payoffs, overlap, entries, samples)
    order_stats_mu, order_stats_sigma, opp_cov = get_order_stats(slate, payoffs, entries, samples)
    return PGATournyOptimData(slate, overlap, payoffs, order_stats_mu, order_stats_sigma, opp_cov)
end
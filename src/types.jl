using LinearAlgebra
using JuMP


abstract type Slate end

struct MLBSlate <: Slate
    # Writing this out explicity helps type stability and ensures that all columns needed are present
    players::Vector{NamedTuple{(:Name, :ID, :Position, :Salary, :Game, :Team, :Opponent, :Order, :Opp_Pitcher, :Projection),Tuple{String,String,String,Int64,String,String,String,Int64,Union{Missing,String},Float64}}}
    games::AbstractVector{AbstractString}
    teams::AbstractVector{AbstractString}
    μ::AbstractVector{<:Real}
    Σ::Symmetric{<:Real}
end
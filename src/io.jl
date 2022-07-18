using Tables
using CSV
include("types.jl")


"""
    makeposdef(mat::Symmetric{<:Real})

Transforms a Symmetric real-valued matrix into a positive definite matrix
Computes eigendecomposition of matrix, sets negative and zero eigenvalues
to small value (1e-10) and then reconstructs matrix
"""
function makeposdef(mat::Symmetric{<:Real})
    vals = eigvals(mat)
    vecs = eigvecs(mat)
    vals[vals.<=1e-10] .= 1e-10
    return Symmetric(vecs * Diagonal(vals) * vecs')
end


"""
    get_mlb_slate(date::String)

Constructs MLBSlate given a date.
"""
function get_mlb_slate(date::AbstractString)
    players = CSV.read("./data/slates/slate_$(date).csv", Tables.rowtable)
    μ = [player.Projection for player in players]
    Σ = makeposdef(Symmetric(CSV.read("./data/slates/cov_$(date).csv", header=false, Tables.matrix)))
    games = unique([player.Game for player in players])
    teams = unique([player.Team for player in players])
    return MLBSlate(players, games, teams, μ, Σ)
end


"""
    transform_lineup(lineup::JuMP.Containers.DenseAxisArray)

Transforms lineup vector from optimization to a dict mapping between roster position and player ID
"""
function transform_lineup(slate::MLBSlate, lineup::JuMP.Containers.DenseAxisArray)
    # Roster positions to fill
    positions = Dict{String,Union{String,Missing}}("P1" => missing,
        "P2" => missing,
        "C" => missing,
        "1B" => missing,
        "2B" => missing,
        "3B" => missing,
        "SS" => missing,
        "OF1" => missing,
        "OF2" => missing,
        "OF3" => missing)
    for player in slate.players
        # If player is selected
        if value(lineup[player.ID]) == 1
            # If pitcher, fill open pitcher lost
            if player.Position == "P"
                if ismissing(positions["P1"])
                    positions["P1"] = player.ID
                elseif ismissing(positions["P2"])
                    positions["P2"] = player.ID
                end
            end
            # If they're OF, fill open OF slot
            if player.Position == "OF"
                if ismissing(positions["OF1"])
                    positions["OF1"] = player.ID
                elseif ismissing(positions["OF2"])
                    positions["OF2"] = player.ID
                elseif ismissing(positions["OF3"])
                    positions["OF3"] = player.ID
                end
            else
                # Otherwise, fill players position
                positions[player.Position] = player.ID
            end
        end
    end
    return positions
end


"""
    write_lineups(lineups::Vector{Dict{String, String}})

Writes multiple tournament lineups to toury_lineups.csv
"""
function write_lineups(lineups::AbstractVector{Dict{AbstractString,Union{Missing,AbstractString}}})
    open("./tourny_lineups.csv", "w") do file
        println(file, "P,P,C,1B,2B,3B,SS,OF,OF,OF")
        for lineup in lineups
            println(file, "$(lineup["P1"]),$(lineup["P2"]),$(lineup["C"]),$(lineup["1B"]),$(lineup["2B"]),$(lineup["3B"]),$(lineup["SS"]),$(lineup["OF1"]),$(lineup["OF2"]),$(lineup["OF3"])")
        end
    end
end


"""
    write_lineups(points <: Number, lineup::Dict{String,String})

Writes cash game lineup to file with expected points
"""
function write_lineup(points::Number, lineup::AbstractDict{AbstractString,Union{Missing,AbstractString}})
    open("./cash_lineup.csv", "w") do file
        println(file, "Projected Points: $(points)")
        println(file, "P,P,C,1B,2B,3B,SS,OF,OF,OF")
        println(file, "$(lineup["P1"]),$(lineup["P2"]),$(lineup["C"]),$(lineup["1B"]),$(lineup["2B"]),$(lineup["3B"]),$(lineup["SS"]),$(lineup["OF1"]),$(lineup["OF2"]),$(lineup["OF3"])")
    end
end


open("./test.csv", "w") do file
    for x in nym
        println(file, values(x))
    end
    for x in chc
        println(file, values(x))
    end
end
using Tables
using CSV
include("types.jl")
include("cov.jl")


"""
    get_mlb_slate(date::String)

Constructs MLBSlate given a date.
"""
function get_mlb_slate(date::AbstractString)
    players = CSV.read("./data/mlb_slates/$(date).csv", Tables.rowtable)
    hist = CSV.read("./data/mlb_hist.csv", Tables.rowtable)
    μ = [player.Projection for player in players]
    Σ = get_mlb_cov(players, hist)
    games = unique([player.Game for player in players])
    teams = unique([player.Team for player in players])
    return MLBSlate(players, games, teams, μ, Σ)
end


"""
    get_pga_slate(date::String)

Constructs PGASlate given a date.
"""
function get_pga_slate(date::AbstractString)
    players = CSV.read("./data/pga_slates/$(date).csv", Tables.rowtable)
    hist = CSV.read("./data/pga_hist.csv", Tables.rowtable)
    μ = [player.Projection for player in players]
    Σ = get_pga_cov(players, hist)
    return PGASlate(players, μ, Σ)
end


"""
    transform_lineup(slate::MLBSlate, lineup::AbstractVector{<:Integer})

Transforms lineup vector from optimization to a dict mapping between roster position and player ID
"""
function transform_lineup(slate::MLBSlate, lineup::AbstractVector{<:Integer})
    # Roster positions to fill
    positions = Dict{String,Union{Int64,Missing}}(
        "P1" => missing,
        "P2" => missing,
        "C" => missing,
        "1B" => missing,
        "2B" => missing,
        "3B" => missing,
        "SS" => missing,
        "OF1" => missing,
        "OF2" => missing,
        "OF3" => missing
    )
    p = length(slate.players)
    for i in 1:p
        # If player is selected
        if value(lineup[i]) == 1
            player = slate.players[i]
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
    transform_lineup(slate::PGASlate, lineup::AbstractVector{<:Integer})

Transforms lineup vector from optimization to a dict mapping between roster position and player ID
"""
function transform_lineup(slate::PGASlate, lineup::AbstractVector{<:Integer})
    # Roster positions to fill
    positions = Dict{String,Union{Int64,Missing}}(
        "G1" => missing,
        "G2" => missing,
        "G3" => missing,
        "G4" => missing,
        "G5" => missing,
        "G6" => missing
    )
    p = length(slate.players)
    for i in 1:p
        # If player is selected
        if value(lineup[i]) == 1
            player = slate.players[i]
            # If pitcher, fill open pitcher lost
            if ismissing(positions["G1"])
                positions["G1"] = player.ID
            elseif ismissing(positions["G2"])
                positions["G2"] = player.ID
            elseif ismissing(positions["G3"])
                positions["G3"] = player.ID
            elseif ismissing(positions["G4"])
                positions["G4"] = player.ID
            elseif ismissing(positions["G5"])
                positions["G5"] = player.ID
            elseif ismissing(positions["G5"])
                positions["G5"] = player.ID
            elseif ismissing(positions["G6"])
                positions["G6"] = player.ID
            end
        end
    end
    return positions
end


"""
    write_lineups(lineups::Vector{Dict{String, String}})

Writes multiple tournament lineups to mlb_lineups.csv
"""
function write_lineups(slate::MLBSlate, lineups::AbstractVector{<:AbstractVector{<:Integer}})
    open("./mlb_lineups.csv", "w") do file
        println(file, "P,P,C,1B,2B,3B,SS,OF,OF,OF")
        for lineup in lineups
            lineup_dict = transform_lineup(slate, lineup)
            println(file, "$(lineup_dict["P1"]),$(lineup_dict["P2"]),$(lineup_dict["C"]),$(lineup_dict["1B"]),$(lineup_dict["2B"]),$(lineup_dict["3B"]),$(lineup_dict["SS"]),$(lineup_dict["OF1"]),$(lineup_dict["OF2"]),$(lineup_dict["OF3"])")
        end
    end
end


"""
    write_lineups(lineups::Vector{Dict{String, String}})

Writes multiple tournament lineups to pga_lineups.csv
"""
function write_lineups(slate::PGASlate, lineups::AbstractVector{<:AbstractVector{<:Integer}})
    open("./pga_lineups.csv", "w") do file
        println(file, "G,G,G,G,G,G")
        for lineup in lineups
            lineup_dict = transform_lineup(slate, lineup)
            println(file, "$(lineup_dict["G1"]),$(lineup_dict["G2"]),$(lineup_dict["G3"]),$(lineup_dict["G4"]),$(lineup_dict["G5"]),$(lineup_dict["G6"])")
        end
    end
end
include("./src/solve.jl")

files = readdir("./data/realized_slates")
dates = [file[1:10] for file in files if ~occursin("cov", file)]
overlaps = [3, 4, 5, 6, 7]

for date in dates
    players = CSV.read("./data/realized_slates/$(date).csv", Tables.rowtable)
    μ = [player.Projection for player in players]
    scored = [player.Scored for player in players]
    Σ = makeposdef(Symmetric(CSV.read("./data/realized_slates/$(date)_cov.csv", header=false, Tables.matrix)))
    games = unique([player.Game for player in players])
    teams = unique([player.Team for player in players])
    slate = MLBSlate(players, games, teams, μ, Σ)

    for overlap in overlaps
        lineups = tourny_lineups(slate, 10, overlap)
        realized_scores = Vector{Float64}(undef, length(lineups))
        for i in 1:length(lineups)
            realized_scores[i] = lineups[i]' * scored
        end
        open("./results.csv", "a") do file
            println(file, "$(date),$(length(games)),10,$(overlap),$(maximum(realized_scores))")
        end
    end
end
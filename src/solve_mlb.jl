using Dates
include("optim.jl")
include("types.jl")
include("io.jl")
include("opp_teams.jl")

println("Getting slate")
# SET PARAMETER: slate date
slate = get_mlb_slate("2022-08-04")
# SET PARAMETER: payoffs
payoffs = Tuple{Int64,Float64}[
    (1, 1000.0),
    (2, 500.0),
    (3, 250.0),
    (4, 150.0),
    (5, 100.0),
    (6, 75.0),
    (7, 50.0),
    (9, 30.0),
    (11, 25.0),
    (15, 20.0),
    (20, 15.0),
    (26, 10.0),
    (36, 8.0),
    (46, 6.0),
    (61, 5.0),
    (101, 4.0),
    (196, 3.0),
    (406, 2.0),
    (866, 1.5),
    (1812, 1.0),
    (5468, 0.0)
]
println("Making optim data")
# SET PARAMETER: Overlap, total entries, and samples
data = MLBTournyOptimData(slate, payoffs, 7, 23700, 250)
println("Getting lineups")
# SET PARAMETER: number of lineups to generate
lineups = tourny_lineups(data, 50)
println("Writing lineups")
write_lineups(slate, lineups)
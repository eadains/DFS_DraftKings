using Dates
include("optim.jl")
include("types.jl")
include("io.jl")
include("opp_teams.jl")

# SET PARAMETER: slate date
println("Getting slate")
slate = get_pga_slate("2022-08-25")
# SET PARAMETER: payoffs
# 40k 95100 entry contest
# payoffs = Tuple{Int64,Float64}[
#     (1, 4000.0),
#     (2, 1500.0),
#     (3, 1000.0),
#     (4, 750.0),
#     (5, 500.0),
#     (6, 250.0),
#     (7, 200.0),
#     (9, 150.0),
#     (11, 100.0),
#     (16, 75.0),
#     (21, 60.0),
#     (31, 50.0),
#     (41, 40.0),
#     (51, 30.0),
#     (66, 25.0),
#     (86, 20.0),
#     (111, 15.0),
#     (141, 10.0),
#     (186, 8.0),
#     (241, 6.0),
#     (316, 5),
#     (436, 4.0),
#     (691, 3.0),
#     (1331, 2.0),
#     (3046, 1.5),
#     (6616, 1.0),
#     (19976, 0.0)
# ]
# 25k
payoffs = Tuple{Int64,Float64}[
    (1, 2500.0),
    (2, 1000.0),
    (3, 600.0),
    (4, 400.0),
    (5, 250.0),
    (6, 200.0),
    (7, 150.0),
    (9, 100.0),
    (11, 75.0),
    (15, 60.0),
    (20, 50.0),
    (26, 40.0),
    (36, 30.0),
    (46, 25.0),
    (56, 20.0),
    (71, 15.0),
    (91, 10.0),
    (121, 8.0),
    (161, 6.0),
    (211, 5.0),
    (291, 4.0),
    (461, 3.0),
    (881, 2.0),
    (1991, 1.5),
    (4277, 1.0),
    (12468, 0.0)
]
println("Making optim data")
# SET PARAMETER: Overlap, total entries, and samples
data = PGATournyOptimData(slate, payoffs, 4, 59453, 250)
# SET PARAMETER: number of lineups to generate
println("Getting lineups")
lineups = tourny_lineups(data, 50)
println("Writing lineups")
write_lineups(slate, lineups)
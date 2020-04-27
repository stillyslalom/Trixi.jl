module TimeDisc

using ..Trixi
using ..Solvers: AbstractSolver, rhs!, calc_total_math_entropy
using ..Auxiliary: timer, parameter
using TimerOutputs: @timeit
using Roots: find_zero, Order0

export timestep!


# Carpenter's 4th-order 5-stage low-storage Runge-Kutta method
function timestep!(solver::AbstractSolver, ::Val{:carpenter_4_5}, t::Float64, dt::Float64)
  # Coefficients for Carpenter's 5-stage 4th-order low-storage Runge-Kutta method
  a = [0.0, 567301805773.0 / 1357537059087.0,2404267990393.0 / 2016746695238.0,
       3550918686646.0 / 2091501179385.0, 1275806237668.0 / 842570457699.0]
  b = [1432997174477.0 / 9575080441755.0, 5161836677717.0 / 13612068292357.0,
       1720146321549.0 / 2090206949498.0, 3134564353537.0 / 4481467310338.0,
       2277821191437.0 / 14882151754819.0]
  c = [0.0, 1432997174477.0 / 9575080441755.0, 2526269341429.0 / 6820363962896.0,
       2006345519317.0 / 3224310063776.0, 2802321613138.0 / 2924317926251.0]
  
  for stage = 1:5
    t_stage = t + dt * c[stage]
    @timeit timer() "rhs" rhs!(solver, t_stage)
    @timeit timer() "Runge-Kutta step" begin
      @. solver.elements.u_rungekutta = (solver.elements.u_t
                                        - solver.elements.u_rungekutta * a[stage])
      @. solver.elements.u += solver.elements.u_rungekutta * b[stage] * dt
    end
  end
end


# Standard ("the") 4th-order 4-stage Runge-Kutta method
function timestep!(solver::AbstractSolver, ::Val{:rk_4_4}, t::Float64, dt::Float64)
  @timeit timer() "Runge-Kutta step" begin
    # Introduce variables for convenience
    u = solver.elements.u
    u_t = solver.elements.u_t
    u0 = solver.elements.u_rungekutta

    # Init storage
    k1 = similar(u)
    k2 = similar(u)
    k3 = similar(u)
    k4 = similar(u)

    # Init RK coefficients
    b = [1/6, 1/3, 1/3, 1/6]
    c = [0, 1/2, 1/2, 1]

    # Store initial solution
    @. u0 = u

    # Get parameter that enables EC/ES time discretization
    timedisc_relaxation = parameter("timedisc_relaxation", "off", valid=("off", "ec", "es"))
  end

  # Calculate RK stages
  @timeit timer() "rhs" rhs!(solver, t + c[1])
  # Stage 1 + update u
  @timeit timer() "Runge-Kutta step" begin
    @. k1 = u_t
    @. u = u0 + 1/2 * dt * k1
  end
  # Stage 2 + update u
  @timeit timer() "rhs" rhs!(solver, t + c[2])
  @timeit timer() "Runge-Kutta step" begin
    @. k2 = u_t
    @. u = u0 + 1/2 * dt * k2
  end
  # Stage 3 + update u
  @timeit timer() "rhs" rhs!(solver, t + c[3])
  @timeit timer() "Runge-Kutta step" begin
    @. k3 = u_t
    @. u = u0 + dt * k3
  end
  # Stage 4 + update u
  @timeit timer() "rhs" rhs!(solver, t + c[4])
  @timeit timer() "Runge-Kutta step" begin
    @. k4 .= u_t
    @. u = u0 + dt * (b[1]*k1 + b[2]*k2 + b[3]*k3 + b[4]*k4)
  end

  # Run relaxation if enabled
  if timedisc_relaxation in ("ec", "es")
    @timeit timer() "Runge-Kutta step" begin
      @timeit timer() "relaxation" begin
        d = similar(u)
        @. d = b[1]*k1 + b[2]*k2 + b[3]*k3 + b[4]*k4
        e = 0.0

        @. u = u0
        initial_entropy = calc_total_math_entropy(solver)

        function r(gamma)
          @. u = u0 + gamma * dt * d
          new_entropy = calc_total_math_entropy(solver)
          return new_entropy - initial_entropy
        end

        gamma = find_zero(r, 1, Order0())

        @. u = u0 + gamma * dt * d
      end
    end
  end
end


end

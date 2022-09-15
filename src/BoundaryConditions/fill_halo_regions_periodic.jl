using KernelAbstractions.Extras.LoopInfo: @unroll

#####
##### Periodic boundary conditions
#####

@inline parent_and_size(c, dim1, dim2, size)     = (parent(c),  size)
@inline parent_and_size(c, dim1, dim2, ::Symbol) = (parent(c),  size(parent(c))[[dim1, dim2]])

@inline function parent_and_size(c::NTuple, dim1, dim2, ::Symbol)
    p = parent.(c)
    p_size = (minimum([size(t, dim1) for t in p]), minimum([size(t, dim2) for t in p]))
    return p, p_size
end

@inline fix_halo_offsets(o, co) = co > 0 ? o - co : o # Windowed fields have only positive offsets to correct

function fill_west_and_east_halo!(c, ::PBCT, ::PBCT, size, offset, loc, arch, dep, grid, args...; kw...)
    c_parent, yz_size = parent_and_size(c, 2, 3, size)
    offset = fix_halo_offsets.(offset, c.offsets[[2, 3]]) 
    event = launch!(arch, grid, yz_size, fill_periodic_west_and_east_halo!, c_parent, offset, grid.Hx, grid.Nx; dependencies=dep, kw...)
    return event
end

function fill_south_and_north_halo!(c, ::PBCT, ::PBCT, size, offset, loc, arch, dep, grid, args...; kw...)
    c_parent, xz_size = parent_and_size(c, 1, 3, size)
    offset = fix_halo_offsets.(offset, c.offsets[[1, 3]]) 
    event = launch!(arch, grid, xz_size, fill_periodic_south_and_north_halo!, c_parent, offset, grid.Hy, grid.Ny; dependencies=dep, kw...)
    return event
end

function fill_bottom_and_top_halo!(c, ::PBCT, ::PBCT, size, offset, loc, arch, dep, grid, args...; kw...)
    c_parent, xy_size = parent_and_size(c, 1, 2, size)
    offset = fix_halo_offsets.(offset, c.offsets[[1, 2]]) 
    event = launch!(arch, grid, xy_size, fill_periodic_bottom_and_top_halo!, c_parent, offset, grid.Hz, grid.Nz; dependencies=dep, kw...)
    return event
end

#####
##### Periodic boundary condition kernels
#####

@kernel function fill_periodic_west_and_east_halo!(c, offset, H::Int, N)
    j, k = @index(Global, NTuple)
    j′ = j + offset[1]
    k′ = k + offset[2]
    @unroll for i = 1:H
        @inbounds begin
            c[i, j′, k′]     = c[N+i, j′, k′] # west
            c[N+H+i, j′, k′] = c[H+i, j′, k′] # east
        end
    end
end

@kernel function fill_periodic_south_and_north_halo!(c, offset, H::Int, N)
    i, k = @index(Global, NTuple)
    i′ = i + offset[1]
    k′ = k + offset[2]
    @unroll for j = 1:H
        @inbounds begin
            c[i′, j, k′]     = c[i′, N+j, k′] # south
            c[i′, N+H+j, k′] = c[i′, H+j, k′] # north
        end
    end
end

@kernel function fill_periodic_bottom_and_top_halo!(c, offset, H::Int, N)
    i, j = @index(Global, NTuple)
    i′ = i + offset[1]
    j′ = j + offset[2]
    @unroll for k = 1:H
        @inbounds begin
            c[i′, j′, k]     = c[i′, j′, N+k] # top
            c[i′, j′, N+H+k] = c[i′, j′, H+k] # bottom
        end
    end
end

####
#### Tupled periodic boundary condition 
####

@kernel function fill_periodic_west_and_east_halo!(c::NTuple{M}, offset, H::Int, N) where M
    j, k = @index(Global, NTuple)
    @unroll for n = 1:M
        @unroll for i = 1:H
            @inbounds begin
                  c[n][i, j, k]     = c[n][N+i, j, k] # west
                  c[n][N+H+i, j, k] = c[n][H+i, j, k] # east
            end
        end
    end
end

@kernel function fill_periodic_south_and_north_halo!(c::NTuple{M}, offset, H::Int, N) where M
    i, k = @index(Global, NTuple)
    @unroll for n = 1:M
        @unroll for j = 1:H
            @inbounds begin
                c[n][i, j, k]     = c[n][i, N+j, k] # south
                c[n][i, N+H+j, k] = c[n][i, H+j, k] # north
            end
        end
    end
end

@kernel function fill_periodic_bottom_and_top_halo!(c::NTuple{M}, offset, H::Int, N) where M
    i, j = @index(Global, NTuple)
    @unroll for n = 1:M
        @unroll for k = 1:H
            @inbounds begin
                c[n][i, j, k]     = c[n][i, j, N+k] # top
                c[n][i, j, N+H+k] = c[n][i, j, H+k] # bottom
            end  
        end
    end
end

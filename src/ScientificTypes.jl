module ScientificTypes

export Scientific, Found, Unknown, Finite, Infinite
export OrderedFactor, Multiclass, Count, Continuous
export Binary, Table, ColorImage, GrayImage
export scitype, scitype_union, scitypes, coerce, schema
export mlj

using Requires, InteractiveUtils

# ## FOR DEFINING SCITYPES ON OBJECTS DETECTED USING TRAITS

# We define a "dynamically" extended function `trait`:

const TRAIT_FUNCTION_GIVEN_NAME = Dict()
function trait(X)
    for (name, f) in TRAIT_FUNCTION_GIVEN_NAME
        f(X) && return name
    end
    return :other
end

# Explanation: For example, if Tables.jl is loaded and one does
# `TRAIT_FUNCTION_GIVEN_NAME[:table] = Tables.is_table` then
# `trait(X)` returns `:table` on any Tables.jl table, and `:other`
# otherwise. There is an understanding here that no two trait
# functions added to the dictionary values can be simultaneously true
# on two julia objects.


# ## CONVENTIONS

const CONVENTION=[:unspecified]
convention() = CONVENTION[1]

function mlj()
    CONVENTION[1] = :mlj
    return nothing
end


# ## THE SCIENTIFIC TYPES

abstract type Found          end
abstract type Known <: Found end
struct      Unknown <: Found end

abstract type Infinite <: Known    end
struct      Continuous <: Infinite end
struct           Count <: Infinite end

abstract type Finite{N} <: Known     end
struct    Multiclass{N} <: Finite{N} end
struct OrderedFactor{N} <: Finite{N} end

abstract type Image{W,H} <: Known      end
struct    GrayImage{W,H} <: Image{W,H} end
struct   ColorImage{W,H} <: Image{W,H} end

# aliases:
const Binary     = Finite{2}
const Scientific = Union{Missing,Found}

"""
    MLJBase.Table{K}

The scientific type for tabular data (a containter `X` for which
`Tables.is_table(X)=true`).

If `X` has columns `c1, c2, ..., cn`, then, by definition,

    scitype(X) = Table{Union{scitype(c1), scitype(c2), ..., scitype(cn)}}

A special constructor of `Table` types exists:

    `Table(T1, T2, T3, ..., Tn) <: Table`

has the property that

    scitype(X) <: Table(T1, T2, T3, ..., Tn)

if and only if `X` is a table *and*, for every column `col` of `X`,
`scitype(col) <: AbstractVector{<:Tj}`, for some `j` between `1` and
`n`. Note that this constructor constructs a *type* not an instance,
as instances of scientific types play no role (except for missing).

    julia> X = (x1 = [10.0, 20.0, missing],
                x2 = [1.0, 2.0, 3.0],
                x3 = [4, 5, 6])

    julia> scitype(X) <: MLJBase.Table(Continuous, Count)
    false

    julia> scitype(X) <: MLJBase.Table(Union{Continuous, Missing}, Count)
    true

"""
struct Table{K} <: Known end
function Table(Ts...)
    Union{Ts...} <: Scientific ||
        error("Arguments of Table scitype constructor "*
              "must be scientific types. ")
    return Table{<:Union{[AbstractVector{<:T} for T in Ts]...}}
end


# ## THE SCITYPE FUNCTION

"""
    scitype(x)

The scientific type that `x` may represent.

"""
scitype(X) = scitype(X, Val(convention()))
scitype(X, C) = scitype(X, C, Val(trait(X)))
scitype(X, C, ::Val{:other}) = Unknown

scitype(::Missing) = Missing


# ## CONVENIENCE METHOD FOR UNIONS OVER ELEMENTS

"""
    scitype_union(A)

Return the type union, over all elements `x` generated by the iterable
`A`, of `scitype(x)`.

See also `scitype`.

"""
scitype_union(A) = reduce((a,b)->Union{a,b}, (scitype(el) for el in A))


# ## SCITYPES OF TUPLES AND ARRAYS

scitype(t::Tuple, ::Val) = Tuple{scitype.(t)...}
scitype(A::B, ::Val) where {T,N,B<:AbstractArray{T,N}} =
    AbstractArray{scitype_union(A),N}


# ## STUB FOR COERCE METHOD

function coerce end


# ## TABLE SCHEMA

struct Schema{names, types, scitypes, nrows} end

Schema(names::Tuple{Vararg{Symbol}}, types::Type{T}, scitypes::Type{S}, nrows::Integer) where {T<:Tuple,S<:Tuple} = Schema{names, T, S, nrows}()
Schema(names, types, scitypes, nrows) = Schema{Tuple(Base.map(Symbol, names)), Tuple{types...}, Tuple{scitypes...}, nrows}()

function Base.getproperty(sch::Schema{names, types, scitypes, nrows}, field::Symbol) where {names, types, scitypes, nrows}
    if field === :names
        return names
    elseif field === :types
        return types === nothing ? nothing : Tuple(fieldtype(types, i) for i = 1:fieldcount(types))
    elseif field === :scitypes
        return scitypes === nothing ? nothing : Tuple(fieldtype(scitypes, i) for i = 1:fieldcount(scitypes))
    elseif field === :nrows
        return nrows === nothing ? nothing : nrows
    else
        throw(ArgumentError("unsupported property for ScientificTypes.Schema"))
    end
end

Base.propertynames(sch::Schema) = (:names, :types, :scitypes, :nrows)

_as_named_tuple(s::Schema) = NamedTuple{(:names, :types, :scitypes, :nrows)}((s.names, s.types, s.scitypes, s.nrows))

function Base.show(io::IO, ::MIME"text/plain", s::Schema)
    show(io, MIME("text/plain"), _as_named_tuple(s))
end


"""
    schema(X)

Inspect the column types and scitypes of a table.

    julia> X = (ncalls=[1, 2, 4], mean_delay=[2.0, 5.7, 6.0])
    julia> schema(X)
    (names = (:ncalls, :mean_delay),
     types = (Int64, Float64),
     scitypes = (Count, Continuous))

"""
schema(X) = schema(X, Val(trait(X)))
schema(X, ::Val{:other}) =
    throw(ArgumentError("Cannot inspect the internal scitypes of "*
                        "an object with trait `:other`\n"*
                        "Perhaps you meant to import Tables first?"))


## ACTIVATE DEFAULT CONVENTION

# and include code not requring optional dependencies:

mlj()
include("conventions/mlj/mlj.jl")


## FOR LOADING OPTIONAL DEPENDENCIES

function __init__()

    # for printing out the type tree:
    @require(AbstractTrees = "1520ce14-60c1-5f80-bbc7-55ef81b5835c",
             include("tree.jl"))

    # the scitype and schema of tabular data:
    @require(Tables="bd369af6-aec1-5ad0-b16a-f7cc5008161c",
             (include("tables.jl"); include("autotype.jl")))

    # :mlj conventions requiring external packages
    @require(CategoricalArrays="324d7699-5711-5eae-9e2f-1d82baa6b597",
             include("conventions/mlj/finite.jl"))
    @require(ColorTypes="3da002f7-5984-5a60-b8a6-cbb66c0b333f",
             include("conventions/mlj/images.jl"))

end

end # module

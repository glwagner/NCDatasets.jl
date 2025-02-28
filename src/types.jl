#=
Core type of `NCDatasets`
the `Attributes` and `Group` parts as well.
and the `Attributes` part of it.

High-level interface is at the "High-level" section about actually
loading/reading/making datasets.
=#

# Exception type for error thrown by the NetCDF library
mutable struct NetCDFError <: Exception
    code::Cint
    msg::String
end


struct CFStdName
    name::Symbol
end

# base type of attributes list
# concrete types are Attributes (single NetCDF file) and
# MFAttributes (multiple NetCDF files)

abstract type BaseAttributes
end

abstract type AbstractDataset
end


abstract type AbstractDimensions
end

abstract type AbstractGroups
end


############################################################
# Types and subtypes
############################################################

# List of attributes (for a single NetCDF file)
# all ids should be Cint

mutable struct Attributes{TDS<:AbstractDataset} <: BaseAttributes
    ds::TDS
    varid::Cint
end

mutable struct Groups{TDS<:AbstractDataset} <: AbstractGroups
    ds::TDS
end

mutable struct Dimensions{TDS<:AbstractDataset} <: AbstractDimensions
    ds::TDS
end

abstract type AbstractVariable{T,N} <: AbstractArray{T,N} end

# Variable (as stored in NetCDF file, without using
# add_offset, scale_factor and _FillValue)
mutable struct Variable{NetCDFType,N,TDS<:AbstractDataset} <: AbstractVariable{NetCDFType, N}
    ds::TDS
    varid::Cint
    dimids::NTuple{N,Cint}
    attrib::Attributes{TDS}
end

mutable struct NCDataset{TDS} <: AbstractDataset where TDS <: Union{AbstractDataset,Nothing}
    # parent_dataset is nothing for the root dataset
    parentdataset::TDS
    ncid::Cint
    iswritable::Bool
    # true of the NetCDF is in define mode (i.e. metadata can be added, but not data)
    # need to be a reference, so that remains syncronised when copied
    isdefmode::Ref{Bool}
    attrib::Attributes{NCDataset{TDS}}
    dim::Dimensions{NCDataset{TDS}}
    group::Groups{NCDataset{TDS}}
    # mapping between variables related via the bounds attribute
    # It is only used for read-only datasets to improve performance
    _boundsmap::Dict{String,String}
    function NCDataset(ncid::Integer,
                       iswritable::Bool,
                       isdefmode::Ref{Bool};
                       parentdataset = nothing,
                       )

        function _finalize(ds)
            @debug begin
                ccall(:jl_, Cvoid, (Any,), "finalize $ncid $timeid \n")
            end
            # only close open root group
            if (ds.ncid != -1) && (ds.parentdataset == nothing)
                close(ds)
            end
        end
        ds = new{typeof(parentdataset)}()
        ds.parentdataset = parentdataset
        ds.ncid = ncid
        ds.iswritable = iswritable
        ds.isdefmode = isdefmode
        ds.attrib = Attributes(ds,NC_GLOBAL)
        ds.dim = Dimensions(ds)
        ds.group = Groups(ds)
        ds._boundsmap = Dict{String,String}()
        if !iswritable
            initboundsmap!(ds)
        end
        timeid = Dates.now()
        @debug "add finalizer $ncid $(timeid)"
        finalizer(_finalize, ds)
        return ds
    end
end

"Alias to `NCDataset`"
const Dataset = NCDataset


# Variable (with applied transformations following the CF convention)
mutable struct CFVariable{T,N,TV,TA,TSA}  <: AbstractVariable{T, N}
    # this var is generally a `Variable` type
    var::TV
    # Dict-like object for all attributes read from disk
    attrib::TA
    # a named tuple with fill value, scale factor, offset,...
    # immutable for type-stability
    _storage_attrib::TSA
end


# Multi-file related type definitions

mutable struct MFAttributes{T} <: BaseAttributes where T <: BaseAttributes
    as::Vector{T}
end

function Base.getindex(a::MFAttributes,name::AbstractString)
    return a.as[1][name]
end

function Base.setindex!(a::MFAttributes,data,name::AbstractString)
    for a in a.as
        a[name] = data
    end
    return data
end

mutable struct MFVariable{T,N,M,TA,A,TDS} <: AbstractVariable{T,N}
    ds::TDS
    var::CatArrays.CatArray{T,N,M,TA}
    attrib::MFAttributes{A}
    dimnames::NTuple{N,String}
    varname::String
end

mutable struct MFCFVariable{T,N,M,TA,TV,A,TDS} <: AbstractVariable{T,N}
    ds::TDS
    cfvar::CatArrays.CatArray{T,N,M,TA}
    var::TV
    attrib::MFAttributes{A}
    dimnames::NTuple{N,String}
    varname::String
end

mutable struct MFDimensions{T} <: AbstractDimensions where T <: AbstractDimensions
    as::Vector{T}
    aggdim::String
    isnewdim::Bool
end

mutable struct MFGroups{T} <: AbstractGroups where T <: AbstractGroups
    as::Vector{T}
    aggdim::String
    isnewdim::Bool
end

mutable struct MFDataset{T,N,S<:AbstractString,TA,TD,TG} <: AbstractDataset where T <: AbstractDataset
    ds::Array{T,N}
    aggdim::S
    isnewdim::Bool
    constvars::Vector{Symbol}
    attrib::MFAttributes{TA}
    dim::MFDimensions{TD}
    group::MFGroups{TG}
    _boundsmap::Dict{String,String}
end


# DeferDataset are Dataset which are open only when there are accessed and
# closed directly after. This is necessary to work with a large number
# of NetCDF files (e.g. more than 1000).

struct Resource
    filename::String
    mode::String
    metadata::OrderedDict
end

mutable struct DeferAttributes <: BaseAttributes
    r::Resource
    varname::String # "/" for global attributes
    data::OrderedDict
end

mutable struct DeferDimensions <: AbstractDimensions
    r::Resource
    data::OrderedDict
end

mutable struct DeferGroups <: AbstractGroups
    r::Resource
    data::OrderedDict
end

mutable struct DeferDataset <: AbstractDataset
    r::Resource
    groupname::String
    attrib::DeferAttributes
    dim::DeferDimensions
    group::DeferGroups
    data::OrderedDict
    _boundsmap::Union{Nothing,Dict{String,String}}
end

mutable struct DeferVariable{T,N} <: AbstractVariable{T,N}
    r::Resource
    varname::String
    attrib::DeferAttributes
    data::OrderedDict
end

# view of subsets


struct SubVariable{T,N,TA,TI,TAttrib,TV} <: AbstractVariable{T,N}
    parent::TA
    indices::TI
    attrib::TAttrib
    # unpacked variable
    var::TV
end

struct SubDataset{TD,TI,TDIM,TA,TG}  <: AbstractDataset
    ds::TD
    indices::TI
    dim::TDIM
    attrib::TA
    group::TG
end


struct SubDimensions{TD,TI} <: AbstractDimensions
    dim::TD
    indices::TI
end

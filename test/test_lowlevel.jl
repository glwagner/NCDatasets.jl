using Random
using Test
import NCDatasets

varname = "varname"
filename = tempname()

samples = [
    # Ints
    [1,2,3,4],

    # Floats
    [1. 2. 3.; 4. 5. 6.],

    # chars
    ['a','b','c'],
    ['a' 'b' 'c'; 'd' 'e' 'f'],

    # strings
    ["wieso","weshalb","warum"],
    ["wieso" "weshalb" "warum"; "why" "why" "whyyy"],
    map(x -> randstring(rand(3:10)), zeros(2,3,4)),
]


for sampledata in samples
    local start, varid, varid, T, dimids, ncid, xtype
    rm(filename;force=true)

    # write data
    ncid = NCDatasets.nc_create(filename,NCDatasets.NC_CLOBBER | NCDatasets.NC_NETCDF4)

    dimids = zeros(Cint,ndims(sampledata))
    for i = 1:ndims(sampledata)
        dimids[i] = NCDatasets.nc_def_dim(ncid, "dim-$(i)", size(sampledata,i))
    end

    T = eltype(sampledata)
    xtype = NCDatasets.ncType[T]
    # reverse order
    varid = NCDatasets.nc_def_var(ncid, varname, xtype, reverse(dimids))
    NCDatasets.nc_put_att(ncid, varid, "attr-string-list",["one","two"])
    NCDatasets.nc_put_var(ncid, varid, sampledata)
    NCDatasets.nc_close(ncid)

    # load data
    ncid = NCDatasets.nc_open(filename,NCDatasets.NC_NOWRITE)
    varid = NCDatasets.nc_inq_varid(ncid,varname)
    xtype2 = NCDatasets.nc_inq_vartype(ncid,varid)
    @test xtype == xtype

    attrval = NCDatasets.nc_get_att(ncid, varid, "attr-string-list")
    @test attrval == ["one","two"]

    # test nc_get_var!
    sampledata2 = Array{T,ndims(sampledata)}(undef,size(sampledata))
    NCDatasets.nc_get_var!(ncid,varid,sampledata2)
    @test sampledata == sampledata2

    # test nc_get_vara!
    start = [1 for i in 1:ndims(sampledata)] .- 1
    count = reverse(collect(size(sampledata)))
    NCDatasets.nc_get_vara!(ncid,varid,start,count,sampledata2)
    @test sampledata == sampledata2

    NCDatasets.nc_close(ncid)
end



# accept SubString as file name argument

ncid = NCDatasets.nc_create(filename,NCDatasets.NC_CLOBBER | NCDatasets.NC_NETCDF4)
NCDatasets.nc_close(ncid)

ncid = NCDatasets.nc_open(split("$(filename)#foo",'#')[1],NCDatasets.NC_NOWRITE)
NCDatasets.nc_close(ncid)

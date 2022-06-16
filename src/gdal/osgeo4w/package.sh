export P=gdal
export V=3.5.0
export B=next
export MAINTAINER=JuergenFischer
export BUILDDEPENDS="python3-core swig zlib-devel proj-devel libpng-devel curl-devel geos-devel libmysql-devel sqlite3-devel netcdf-devel libpq-devel expat-devel xerces-c-devel szip-devel hdf4-devel hdf5-devel hdf5-tools ogdi-devel libiconv-devel openjpeg-devel libspatialite-devel freexl-devel libkml-devel xz-devel zstd-devel msodbcsql-devel poppler-devel libwebp-devel oci-devel openfyba-devel freetype-devel python3-devel python3-numpy libjpeg-turbo-devel python3-setuptools opencl-devel libtiff-devel libgeotiff-devel arrow-cpp-devel lz4-devel openssl-devel tiledb-devel lerc-devel kealib-devel"

source ../../../scripts/build-helpers

export PYTHON=Python39

startlog

# should be fixed in the packages
find $(find osgeo4w -name cmake) -type f | \
	xargs sed -i \
		-e 's#.:/src/osgeo4w/src/[^/]*/osgeo4w/install/#\$ENV{OSGEO4W_ROOT}/#g' \
		-e 's#.:/src/osgeo4w/src/[^/]*/osgeo4w/osgeo4w/#\$ENV{OSGEO4W_ROOT}/#g' \
		-e 's#.:\\\\src\\\\osgeo4w\\\\src\\\\[^\\]*\\\\osgeo4w\\\\osgeo4w\\\\#\$ENV{OSGEO4W_ROOT}\\\\#g' \
		-e 's#.:\\\\src\\\\osgeo4w\\\\src\\\\[^\\]*\\\\osgeo4w\\\\install\\\\#\$ENV{OSGEO4W_ROOT}\\\\#g'

[ -f $P-$V.tar.gz ] || {
	wget -q http://download.osgeo.org/gdal/${V%rc*}/$P-$V.tar.gz
	rm -f ../$P-${V%rc*}/patched
}

[ -d ../$P-$V ] || tar -C .. -xzf $P-$V.tar.gz

if ! [ -f ../$P-${V%rc*}/patched ] && [ -z "$OSGEO4W_SKIP_CLEAN" ]; then
	patch -p1 -d ../$P-${V%rc*} --dry-run <patch
	patch -p1 -d ../$P-${V%rc*} <patch
	touch  ../$P-${V%rc*}/patched
fi

[ -f osgeo4w/apps/$PYTHON/Lib/site-packages/setuptools/command/patched ] || {
	patch -p0 --dry-run <easy_install.diff
	patch -p0 <easy_install.diff
	touch osgeo4w/apps/Python39/Lib/site-packages/setuptools/command/patched
}

#
# Download MrSID, ECW and filegdb dependencies
#

mkdir -p gdaldeps
cd gdaldeps

export MRSID_SDK=MrSID_DSDK-9.5.4.4703-win64-vc14
export ECW_ZIP=ECWJP2SDKSetup_5.5.0.1882-Update2-Windows.zip
export ECW_EXE=ECWJP2SDKSetup_5.5.0.1882.exe

for i in \
	https://raw.githubusercontent.com/Esri/file-geodatabase-api/master/FileGDB_API_1.5/FileGDB_API_1_5_VS2015.zip \
	https://downloads.hexagongeospatial.com/software/2020/ECW/$ECW_ZIP \
	http://bin.lizardtech.com/download/developer/$MRSID_SDK.zip \
	; do
	[ -f "${i##*/}" ] || wget -q "$i"
done

mkdir -p filegdb
[ -d filegdb/done ] || {
	unzip -q -o -d filegdb FileGDB_API_1_5_VS2015.zip "bin64/*" "lib64/*" "include/*" license/userestrictions.txt
	touch filegdb/done
}

mkdir -p ecw
[ -f $ECW_EXE ] || unzip -q $ECW_ZIP $ECW_EXE ERDAS_ECW_JPEG2000_SDK.pdf
[ -f ecw/done ] || {
	7z x -aoa -oecw $ECW_EXE \
		'$0/include/*' \
		'lib/vc141/x64/NCSEcw.lib' \
		'lib/vc141/x64/NCSEcwS.lib' \
		'bin/vc141/x64/*' \
		'$TEMP/ecwjp2_sdk/Server_Read-Only_EndUser.rtf'
	mv 'ecw/$0/include' ecw/include
	rmdir 'ecw/$0'
	touch ecw/done
}
[ -f $MRSID_SDK/done ] || {
	unzip -o -q $MRSID_SDK.zip \
		"$MRSID_SDK/Raster_DSDK/include/*" \
		"$MRSID_SDK/Raster_DSDK/lib/*" \
		"$MRSID_SDK/Lidar_DSDK/include/*" \
		"$MRSID_SDK/Lidar_DSDK/lib/*" \
		"$MRSID_SDK/LICENSE.pdf"

	# 'add' VC2019 support
	cp "$MRSID_SDK/Raster_DSDK/include/lt_platform.h" "$MRSID_SDK/Raster_DSDK/include/lt_platform.h.orig"
	sed -i -e 's/#elif defined(_MSC_VER) &&  (1300 <= _MSC_VER && _MSC_VER <= 1910)/#elif defined(_MSC_VER) \&\& (1300 <= _MSC_VER \&\& _MSC_VER < 1930)/' \
		"$MRSID_SDK/Raster_DSDK/include/lt_platform.h"
	touch $MRSID_SDK/done
}

cd ..

major=${V%%.*}
minor=${V#$major.}
minor=${minor%%.*}

export abi=$(printf "%d%02d" $major $minor)

R=$OSGEO4W_REP/x86_64/release/$P
mkdir -p $R/$P-{devel,oracle,filegdb,ecw,mrsid,sosi,mss,hdf5,kea} $R/$P$abi-runtime $R/python3-$P

if [ -f $R/$P-$V-$B-src.tar.bz2 ]; then
	echo "$R/$P-$V-$B-src.tar.bz2 already exists - skipping"
	exit 1
fi

export FGDB_SDK=$(cygpath -am gdaldeps/filegdb)
export ECW_SDK=$(cygpath -am gdaldeps/ecw)
export MRSID_SDK=$(cygpath -am gdaldeps/$MRSID_SDK)

(
	fetchenv osgeo4w/bin/o4w_env.bat

	vs2019env
	cmakeenv
	ninjaenv

	export INCLUDE="$(cygpath -am osgeo4w/include);$(cygpath -am osgeo4w/apps/Python39/include);$(cygpath -am osgeo4w/include/boost-1_74);$INCLUDE"
	export LIB="$(cygpath -am osgeo4w/lib);$LIB"

	mkdir -p build
	cd build

	cmake \
		-G Ninja \
		-D                      CMAKE_BUILD_TYPE=RelWithDebInfo \
		-D                  CMAKE_INSTALL_PREFIX=../install/apps/$P \
		-D                  GDAL_LIB_OUTPUT_NAME=gdal$abi \
		-D                 BUILD_PYTHON_BINDINGS=ON \
		-D             GDAL_USE_GEOTIFF_INTERNAL=OFF \
		-D               GDAL_ENABLE_DRIVER_JPEG=ON \
		-D           GDAL_ENABLE_DRIVER_JP2MRSID=ON \
		-D                OGR_ENABLE_DRIVER_OGDI=ON \
		-D                   GDAL_USE_MSSQL_NCLI=OFF \
		-D                       GDAL_USE_OPENCL=ON \
		-D      OGR_ENABLE_DRIVER_PARQUET_PLUGIN=OFF \
		-D          OGR_ENABLE_DRIVER_OCI_PLUGIN=ON \
		-D        GDAL_ENABLE_DRIVER_GEOR_PLUGIN=ON \
		-D         GDAL_ENABLE_DRIVER_ECW_PLUGIN=ON \
		-D       GDAL_ENABLE_DRIVER_MRSID_PLUGIN=ON \
		-D        GDAL_ENABLE_DRIVER_HDF5_PLUGIN=ON \
		-D         GDAL_ENABLE_DRIVER_KEA_PLUGIN=ON \
		-D      OGR_ENABLE_DRIVER_FILEGDB_PLUGIN=ON \
		-D         OGR_ENABLE_DRIVER_SOSI_PLUGIN=ON \
		-D OGR_ENABLE_DRIVER_MSSQLSPATIAL_PLUGIN=ON \
		-D             Python_NumPy_INCLUDE_DIRS=$(cygpath -am ../osgeo4w/apps/Python39/Lib/site-packages/numpy/core/include) \
		-D                       SWIG_EXECUTABLE=$(cygpath -am ../osgeo4w/bin/swig.bat) \
		-D                       ECW_INCLUDE_DIR=$(cygpath -am ../gdaldeps/ecw/include) \
		-D                           ECW_LIBRARY=$(cygpath -am ../gdaldeps/ecw/lib/vc141/x64/NCSEcw.lib) \
		-D                   FileGDB_INCLUDE_DIR=$(cygpath -am ../gdaldeps/filegdb/include) \
		-D                       FileGDB_LIBRARY=$(cygpath -am ../gdaldeps/filegdb/lib64/FileGDBAPI.lib) \
		-D                     MRSID_INCLUDE_DIR=$(cygpath -am $MRSID_SDK/Raster_DSDK/include) \
		-D                         MRSID_LIBRARY=$(cygpath -am $MRSID_SDK/Raster_DSDK/lib/lti_dsdk.lib) \
		-D                         MYSQL_LIBRARY=$(cygpath -am ../osgeo4w/lib/libmysql.lib) \
		-D                    MSSQL_ODBC_VERSION=17 \
		-D                    MSSQL_ODBC_LIBRARY=$(cygpath -am ../osgeo4w/lib/msodbcsql17.lib) \
		-D                  OPENJPEG_INCLUDE_DIR=$(cygpath -am ../osgeo4w/include/openjpeg-2.4) \
		-D                           Oracle_ROOT=$(cygpath -am ../osgeo4w) \
		-D                        Oracle_LIBRARY=$(cygpath -am ../osgeo4w/lib/oci.lib) \
		-D                          JPEG_LIBRARY=$(cygpath -am ../osgeo4w/lib/jpeg.lib) \
		-D                       LZ4_INCLUDE_DIR=$(cygpath -am ../osgeo4w/include) \
		-D	             LZ4_LIBRARY_RELEASE=$(cygpath -am ../osgeo4w/lib/lz4.lib) \
		-D                   PNG_LIBRARY_RELEASE=$(cygpath -am ../osgeo4w/lib/libpng16.lib) \
		-D   _ICONV_SECOND_ARGUMENT_IS_NOT_CONST=1 \
		-D                         Iconv_LIBRARY=$(cygpath -am ../osgeo4w/lib/iconv.dll.lib) \
		-D                     FYBA_FYBA_LIBRARY=$(cygpath -am ../osgeo4w/lib/fyba.lib) \
		-D                     FYBA_FYGM_LIBRARY=$(cygpath -am ../osgeo4w/lib/gm.lib) \
		-D                     FYBA_FYUT_LIBRARY=$(cygpath -am ../osgeo4w/lib/ut.lib) \
		-D                     OGDI_INCLUDE_DIRS=$(cygpath -am ../osgeo4w/include/ogdi) \
		-D                          OGDI_LIBRARY=$(cygpath -am ../osgeo4w/lib/ogdi.lib) \
		-D                           KEA_LIBRARY=$(cygpath -am ../osgeo4w/lib/libkea.lib) \
		-D                          LERC_LIBRARY=$(cygpath -am ../osgeo4w/lib/Lerc.lib) \
		-D                       SWIG_EXECUTABLE=$(cygpath -am ../osgeo4w/bin/swig.bat) \
		-D             GDAL_EXTRA_LINK_LIBRARIES="$(cygpath -am ../osgeo4w/lib/freetype.lib);$(cygpath -am ../osgeo4w/lib/jpeg.lib);$(cygpath -am ../osgeo4w/lib/tiff.lib);$(cygpath -am ../osgeo4w/lib/uriparser.lib);$(cygpath -am ../osgeo4w/lib/minizip.lib)" \
		../../$P-$V

	[ -n "$OSGEO4W_SKIP_CLEAN" ] || cmake --build . --target clean

	cmake --build .
	cmake --build . --target install || cmake --build . --target install
)

mkdir -p install/etc/{postinstall,preremove}
>install/etc/postinstall/python3-$P.bat
>install/etc/preremove/python3-$P.bat

rm -rf install/apps/$PYTHON
mkdir -p install/apps/$PYTHON/lib
mv install/apps/$P/lib/site-packages install/apps/$PYTHON/lib
mv install/apps/$P/Scripts           install/apps/$PYTHON/

expytmpl=
for i in install/apps/$PYTHON/Scripts/*.py; do
	b=$(basename "$i" .py)

	cat <<EOF >install/apps/$PYTHON/Scripts/$b.bat
@echo off
call "%OSGEO4W_ROOT%\\bin\\o4w_env.bat"
python "%OSGEO4W_ROOT%\\apps\\$PYTHON\\Scripts\\$b.py" %*
EOF
	(
		echo "#! @osgeo4w@\\apps\\$PYTHON\\python3.exe"
		tail -n +2 install/apps/$PYTHON/Scripts/$b.py
	) >install/apps/$PYTHON/Scripts/$b.py.tmpl

	echo -e "textreplace -std -t apps\\$PYTHON\\Scripts\\\\$b.py\r" >>install/etc/postinstall/python3-$P.bat
	echo -e "del apps\\$PYTHON\\Scripts\\\\$b.py\r" >>install/etc/preremove/python3-$P.bat

	expytmpl="$expytmpl --exclude apps/$PYTHON/Scripts/$b.py"
done

echo -e "python -B \"%PYTHONHOME%\\Scripts\\preremove-cached.py\" python3-$P\r" >>install/etc/preremove/python3-$P.bat

mkdir -p install/etc/abi
cat <<EOF >install/etc/abi/$P-devel
$P$abi-runtime
EOF

mkdir -p install/etc/ini
cat <<EOF >install/etc/ini/$P.bat
SET GDAL_DATA=%OSGEO4W_ROOT%\\apps\\$P\\share\\gdal
SET GDAL_DRIVER_PATH=%OSGEO4W_ROOT%\\apps\\$P\\lib\\gdalplugins
EOF

cat <<EOF >$R/setup.hint
sdesc: "The GDAL/OGR library and commandline tools"
ldesc: "The GDAL/OGR library and commandline tools"
maintainer: $MAINTAINER
category: Libs Commandline_Utilities
requires: msvcrt2019 $P$abi-runtime
EOF

cat <<EOF >$R/$P$abi-runtime/setup.hint
sdesc: "The GDAL/OGR $major.$minor runtime library"
ldesc: "The GDAL/OGR $major.$minor runtime library"
maintainer: $MAINTAINER
category: Libs Commandline_Utilities
requires: msvcrt2019 libpng curl geos libmysql sqlite3 netcdf libpq expat xerces-c hdf4 ogdi libiconv openjpeg libspatialite freexl xz zstd poppler msodbcsql libjpeg-turbo arrow-cpp thrift brotli tiledb $RUNTIMEDEPENDS
external-source: $P
EOF

cat <<EOF >$R/$P-devel/setup.hint
sdesc: "The GDAL/OGR headers and libraries"
ldesc: "The GDAL/OGR headers and libraries"
maintainer: $MAINTAINER
category: Libs Commandline_Utilities
requires: $P
external-source: $P
EOF

cat <<EOF >$R/python3-$P/setup.hint
sdesc: "The GDAL/OGR Python3 Bindings and Scripts"
ldesc: "The GDAL/OGR Python3 Bindings and Scripts"
category: Libs
requires: $P$abi-runtime python3-core python3-numpy
maintainer: $MAINTAINER
external-source: $P
EOF

cat <<EOF >$R/$P-oracle/setup.hint
sdesc: "OGR OCI and GDAL GeoRaster Plugins for Oracle"
ldesc: "OGR OCI and GDAL GeoRaster Plugins for Oracle"
category: Libs
requires: $P$abi-runtime oci
maintainer: $MAINTAINER
external-source: $P
EOF

cat <<EOF >$R/$P-filegdb/setup.hint
sdesc: "OGR FileGDB Driver"
ldesc: "OGR FileGDB Driver"
category: Libs
maintainer: $MAINTAINER
requires: $P$abi-runtime
external-source: $P
EOF

cat <<EOF >$R/$P-ecw/setup.hint
sdesc: "ECW Raster Plugin for GDAL"
ldesc: "ECW Raster Plugin for GDAL"
category: Libs
requires: $P$abi-runtime
maintainer: $MAINTAINER
external-source: $P
EOF

cat <<EOF >$R/$P-mrsid/setup.hint
sdesc: "MrSID Raster Plugin for GDAL"
ldesc: "MrSID Raster Plugin for GDAL"
category: Libs
maintainer: $MAINTAINER
requires: $P$abi-runtime
external-source: $P
EOF

cat <<EOF >$R/$P-sosi/setup.hint
sdesc: "OGR SOSI Driver"
ldesc: "The OGR SOSI Driver enables OGR to read data in Norwegian SOSI standard (.sos)"
category: Libs
requires: $P$abi-runtime
maintainer: $MAINTAINER
external-source: $P
EOF

cat <<EOF >$R/$P-mss/setup.hint
sdesc: "OGR plugin with SQL Native Client support for MSSQL Bulk Copy"
ldesc: "OGR plugin with SQL Native Client support for MSSQL Bulk Copy"
category: Libs
requires: $P$abi-runtime
maintainer: $MAINTAINER
external-source: $P
EOF

cat <<EOF >$R/$P-hdf5/setup.hint
sdesc: "HDF5 Plugin for GDAL"
ldesc: "HDF5 Plugin for GDAL"
category: Libs
maintainer: $MAINTAINER
requires: $P$abi-runtime hdf5
external-source: $P
EOF

cat <<EOF >$R/$P-kea/setup.hint
sdesc: "KEA Plugin for GDAL"
ldesc: "KEA Plugin for GDAL"
category: Libs
maintainer: $MAINTAINER
requires: $P$abi-runtime kealib
external-source: $P
EOF

appendversions $R/setup.hint
appendversions $R/$P$abi-runtime/setup.hint
appendversions $R/$P-devel/setup.hint
appendversions $R/python3-$P/setup.hint
appendversions $R/$P-oracle/setup.hint
appendversions $R/$P-filegdb/setup.hint
appendversions $R/$P-ecw/setup.hint
appendversions $R/$P-mrsid/setup.hint
appendversions $R/$P-sosi/setup.hint
appendversions $R/$P-mss/setup.hint
appendversions $R/$P-hdf5/setup.hint
appendversions $R/$P-kea/setup.hint

cp ../$P-${V%rc*}/LICENSE.TXT $R/$P-$V-$B.txt
cp ../$P-${V%rc*}/LICENSE.TXT $R/$P-oracle/$P-oracle-$V-$B.txt
cp ../$P-${V%rc*}/LICENSE.TXT $R/$P$abi-runtime/$P$abi-runtime-$V-$B.txt
cp ../$P-${V%rc*}/LICENSE.TXT $R/$P-devel/$P-devel-$V-$B.txt
cp ../$P-${V%rc*}/LICENSE.TXT $R/$P-mss/$P-mss-$V-$B.txt
cp ../$P-${V%rc*}/LICENSE.TXT $R/$P-sosi/$P-sosi-$V-$B.txt
cp ../$P-${V%rc*}/LICENSE.TXT $R/python3-$P/python3-$P-$V-$B.txt
cp $FGDB_SDK/license/userestrictions.txt $R/$P-filegdb/$P-filegdb-$V-$B.txt
catdoc $ECW_SDK/\$TEMP/ecwjp2_sdk/Server_Read-Only_EndUser.rtf | sed -e "1,/^[^ ]/ { /^$/d }" >$R/$P-ecw/$P-ecw-$V-$B.txt
pdftotext -layout -enc ASCII7 $MRSID_SDK/LICENSE.pdf - >$R/$P-mrsid/$P-mrsid-$V-$B.txt

mkdir -p install/bin
cp $FGDB_SDK/bin64/FileGDBAPI.dll install/bin
cp $ECW_SDK/bin/vc141/x64/NCSEcw.dll install/bin
cp $MRSID_SDK/Raster_DSDK/lib/lti_dsdk_cdll_9.5.dll install/bin
cp $MRSID_SDK/Raster_DSDK/lib/tbb.dll install/bin
cp $MRSID_SDK/Raster_DSDK/lib/lti_dsdk_9.5.dll install/bin
cp $MRSID_SDK/Lidar_DSDK/lib/lti_lidar_dsdk_1.1.dll install/bin

tar -C install -cjvf $R/python3-$P/python3-$P-$V-$B.tar.bz2 \
	--exclude="*.pyc" \
	--exclude="__pycache__" \
	$expytmpl \
	apps/$PYTHON \
	etc/postinstall/python3-$P.bat \
	etc/preremove/python3-$P.bat

tar -C install -cjvf $R/$P-filegdb/$P-filegdb-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/ogr_FileGDB.dll \
	bin/FileGDBAPI.dll

tar -C install -cjvf $R/$P-sosi/$P-sosi-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/ogr_SOSI.dll

tar -C install -cjvf $R/$P-oracle/$P-oracle-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/gdal_GEOR.dll \
	apps/$P/lib/gdalplugins/ogr_OCI.dll

tar -C install -cjvf $R/$P-mss/$P-mss-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/ogr_MSSQLSpatial.dll

tar -C install -cjvf $R/$P-ecw/$P-ecw-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/gdal_ECW_JP2ECW.dll \
	bin/NCSEcw.dll

tar -C install -cjvf $R/$P-hdf5/$P-hdf5-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/gdal_HDF5.dll

tar -C install -cjvf $R/$P-kea/$P-kea-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/gdal_KEA.dll

tar -C install -cjvf $R/$P-mrsid/$P-mrsid-$V-$B.tar.bz2 \
	apps/$P/lib/gdalplugins/gdal_MrSID.dll \
	bin/lti_dsdk_cdll_9.5.dll \
	bin/lti_dsdk_9.5.dll \
	bin/lti_lidar_dsdk_1.1.dll \
	bin/tbb.dll

tar -C install -cjvf $R/$P$abi-runtime/$P$abi-runtime-$V-$B.tar.bz2 \
	--xform "s,apps/$P/bin/gdal$abi.dll,bin/gdal$abi.dll," \
	apps/$P/bin/gdal$abi.dll

tar -C install -cjvf $R/$P-devel/$P-devel-$V-$B.tar.bz2 \
	-h --hard-dereference \
	--exclude "apps/$P/lib/gdalplugins/drivers.ini" \
	--xform "s,apps/$P/include,include," \
	--xform "s,apps/$P/././lib/gdal$abi.lib,lib/gdal.lib," \
	--xform "s,apps/$P/./lib/gdal$abi.lib,lib/gdal_i.lib," \
	--xform "s,apps/$P/lib/gdal$abi.lib,lib/gdal$abi.lib," \
	apps/$P/include \
	apps/$P/././lib/gdal$abi.lib \
	apps/$P/./lib/gdal$abi.lib \
	apps/$P/lib/gdal$abi.lib \
	apps/$P/lib/pkgconfig \
	apps/$P/lib/cmake \
	etc/abi/$P-devel

tar -C install -cjvf $R/$P-$V-$B.tar.bz2 \
	--exclude="apps/$P/lib/gdalplugins/*.dll" \
	--exclude "*.dll" \
	--xform "s,apps/$P/bin/gdal$abi.dll,bin/gdal$abi.dll," \
	--xform "s,apps/$P/bin,bin," \
	apps/$P/lib/gdalplugins/ \
	apps/$P/bin \
	apps/$P/share \
	etc/ini/$P.bat

tar -C .. -cjvf $R/$P-$V-$B-src.tar.bz2 \
	osgeo4w/package.sh \
	osgeo4w/easy_install.diff \
	osgeo4w/patch

(
	find install -type f
	echo install/lib/gdal.lib
	echo install/lib/gdal_i.lib
) |
	sed -re "/\.pyc$/d;
s#^install/##;
/apps\/gdal\/(bin\/|include\/|lib\/gdal.*\.lib$)/ { s/apps\/gdal\///; }
/apps\/$P\/(Scripts|lib\/site-packages)\// { s/apps\/$P\//apps\/$PYTHON\//; }
/apps\/$PYTHON\/Scripts\/.*\.py$/ { s/$/.tmpl/; }
" >/tmp/$P.installed

(
	tar tjf $R/$P-$V-$B.tar.bz2 | tee /tmp/$P.files
	for i in -filegdb -sosi -oracle -mss -ecw -mrsid -hdf5 -kea -devel $abi-runtime; do
		tar tjf $R/$P$i/$P$i-$V-$B.tar.bz2 | tee /tmp/$P-$i.files
	done
	tar tjf $R/python3-$P/python3-$P-$V-$B.tar.bz2 | tee /tmp/python3-$P.files
) >/tmp/$P.packaged

sort /tmp/$P.packaged | uniq -d >/tmp/$P.dupes
if [ -s /tmp/$P.dupes ]; then
	echo Duplicate files:
	cat /tmp/$P.dupes
	false
fi

if fgrep -v -x -f /tmp/$P.packaged /tmp/$P.installed >/tmp/$P.unpackaged; then
	echo Unpackaged files:
	cat /tmp/$P.unpackaged
	false
fi

if fgrep -v -x -f /tmp/$P.installed /tmp/$P.packaged | grep -v "/$" >/tmp/$P.generated; then
	echo Generated files:
	cat /tmp/$P.generated
	false
fi

if [ -s /tmp/$P.dupes ] || [ -s /tmp/$P.unpacked ] || [ -s /tmp/$P.generated ]; then
	exit 1
fi

endlog

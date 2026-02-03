# TRM-Doppler + Lcurve Docker Container
# Multi-stage build for Doppler tomography and light curve modeling software

ARG PYTHON_VERSION=3.11

# =============================================================================
# Stage 1: Build all C++ libraries
# =============================================================================
FROM python:${PYTHON_VERSION}-bookworm AS cpp-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    git \
    libfftw3-dev \
    libpcre3-dev \
    libpcrecpp0v5 \
    libpng-dev \
    libx11-dev \
    gfortran \
    pkg-config \
    wget \
    && rm -rf /var/lib/apt/lists/*

ENV TRM_SOFTWARE=/opt/trm
ENV CPPFLAGS="-I${TRM_SOFTWARE}/include"
ENV LDFLAGS="-L${TRM_SOFTWARE}/lib"
ENV LD_LIBRARY_PATH="${TRM_SOFTWARE}/lib:${LD_LIBRARY_PATH}"
ENV PATH="${TRM_SOFTWARE}/bin:${PATH}"

WORKDIR /build

# -----------------------------------------------------------------------------
# Build PGPLOT (required by subs and others)
# -----------------------------------------------------------------------------
RUN mkdir -p /opt/trm/lib /opt/trm/include /opt/trm/bin && \
    wget -q ftp://ftp.astro.caltech.edu/pub/pgplot/pgplot5.2.tar.gz && \
    tar xzf pgplot5.2.tar.gz && \
    mkdir pgplot_build && cd pgplot_build && \
    cp ../pgplot/drivers.list . && \
    sed -i 's/! PSDRIV/  PSDRIV/' drivers.list && \
    sed -i 's/! XWDRIV/  XWDRIV/' drivers.list && \
    ../pgplot/makemake ../pgplot linux g77_gcc && \
    sed -i 's/g77/gfortran/g' makefile && \
    sed -i 's/FFLAGC=-u/FFLAGC=-u -fallow-argument-mismatch/' makefile && \
    make && make cpg && \
    cp libpgplot.a libcpgplot.a /opt/trm/lib/ && \
    cp cpgplot.h /opt/trm/include/ && \
    cp grfont.dat rgb.txt /opt/trm/lib/ && \
    cd .. && rm -rf pgplot pgplot5.2.tar.gz pgplot_build

# -----------------------------------------------------------------------------
# Build SLALIB (positional astronomy library)
# Using pyslalib (Fortran) + ERFA for missing modern functions
# cpp-subs requires slaEpv and slaPneqx which don't exist in old SLALIB
# We build pyslalib and add ERFA-based wrapper functions for the missing ones
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    liberfa-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/scottransom/pyslalib.git && \
    cd pyslalib && \
    gfortran -c -O2 -fPIC -fallow-argument-mismatch -fno-second-underscore *.f && \
    printf '%s\n' \
      '/* C wrappers for Fortran SLALIB functions */' \
      '#include <erfa.h>' \
      '' \
      '/* Fortran functions - lowercase with trailing underscore */' \
      'extern double sla_airmas_(double*);' \
      'extern void sla_caldj_(int*, int*, int*, double*, int*);' \
      'extern void sla_cldj_(int*, int*, int*, double*, int*);' \
      'extern void sla_dcc2s_(double*, double*, double*);' \
      'extern void sla_dcs2c_(double*, double*, double*);' \
      'extern void sla_dimxv_(double*, double*, double*);' \
      'extern void sla_djcl_(double*, int*, int*, int*, double*, int*);' \
      'extern double sla_dtt_(double*);' \
      'extern double sla_eqeqx_(double*);' \
      'extern double sla_epj_(double*);' \
      'extern void sla_evp_(double*, double*, double*, double*, double*, double*);' \
      'extern void sla_geoc_(double*, double*, double*, double*);' \
      'extern double sla_gmst_(double*);' \
      'extern double sla_pa_(double*, double*, double*);' \
      'extern void sla_pm_(double*, double*, double*, double*, double*, double*, double*, double*, double*, double*);' \
      'extern void sla_pvobs_(double*, double*, double*, double*);' \
      'extern double sla_rcc_(double*, double*, double*, double*, double*);' \
      'extern void sla_refro_(double*, double*, double*, double*, double*, double*, double*, double*, double*, double*);' \
      '' \
      '/* C interface functions */' \
      'double slaAirmas(double zd) { return sla_airmas_(&zd); }' \
      'void slaCaldj(int iy, int im, int id, double *djm, int *j) { sla_caldj_(&iy, &im, &id, djm, j); }' \
      'void slaCldj(int iy, int im, int id, double *djm, int *j) { sla_cldj_(&iy, &im, &id, djm, j); }' \
      'void slaDcc2s(double v[3], double *a, double *b) { sla_dcc2s_(v, a, b); }' \
      'void slaDcs2c(double a, double b, double v[3]) { sla_dcs2c_(&a, &b, v); }' \
      'void slaDimxv(double dm[3][3], double va[3], double vb[3]) { sla_dimxv_((double*)dm, va, vb); }' \
      'void slaDjcl(double djm, int *iy, int *im, int *id, double *fd, int *j) { sla_djcl_(&djm, iy, im, id, fd, j); }' \
      'double slaDtt(double utc) { return sla_dtt_(&utc); }' \
      'double slaEqeqx(double date) { return sla_eqeqx_(&date); }' \
      'double slaEpj(double date) { return sla_epj_(&date); }' \
      'void slaEvp(double date, double deqx, double dvb[3], double dpb[3], double dvh[3], double dph[3]) {' \
      '    sla_evp_(&date, &deqx, dvb, dpb, dvh, dph);' \
      '}' \
      'void slaGeoc(double p, double h, double *r, double *z) { sla_geoc_(&p, &h, r, z); }' \
      'double slaGmst(double ut1) { return sla_gmst_(&ut1); }' \
      'double slaPa(double ha, double dec, double phi) { return sla_pa_(&ha, &dec, &phi); }' \
      'void slaPm(double r0, double d0, double pr, double pd, double px, double rv, double ep0, double ep1, double *r1, double *d1) {' \
      '    sla_pm_(&r0, &d0, &pr, &pd, &px, &rv, &ep0, &ep1, r1, d1);' \
      '}' \
      'void slaPvobs(double p, double h, double stl, double pv[6]) { sla_pvobs_(&p, &h, &stl, pv); }' \
      'double slaRcc(double tdb, double ut1, double wl, double u, double v) { return sla_rcc_(&tdb, &ut1, &wl, &u, &v); }' \
      'void slaRefro(double zobs, double hm, double tdk, double pmb, double rh, double wl, double phi, double tlr, double eps, double *ref) {' \
      '    sla_refro_(&zobs, &hm, &tdk, &pmb, &rh, &wl, &phi, &tlr, &eps, ref);' \
      '}' \
      '' \
      '/* Modern SLALIB functions using ERFA */' \
      'void slaEpv(double date, double ph[3], double vh[3], double pb[3], double vb[3]) {' \
      '    double pvh[2][3], pvb[2][3];' \
      '    eraEpv00(2400000.5, date, pvh, pvb);' \
      '    for (int i = 0; i < 3; i++) { ph[i] = pvh[0][i]; vh[i] = pvh[1][i]; pb[i] = pvb[0][i]; vb[i] = pvb[1][i]; }' \
      '}' \
      'void slaPneqx(double date, double rnpb[3][3]) { eraPnm06a(2400000.5, date, rnpb); }' \
      'void slaI2o(double ri, double di, double utc, double dut, double elong, double phi, double hm,' \
      '    double xp, double yp, double tc, double pm, double rh, double wl, double tlr,' \
      '    double *aob, double *zob, double *hob, double *dob, double *rob) {' \
      '    double astrom[30], eo;' \
      '    eraApco13(2400000.5, utc, dut, elong, phi, hm, xp, yp, pm, tc, rh, wl, astrom, &eo);' \
      '    eraAtioq(ri, di, astrom, aob, zob, hob, dob, rob);' \
      '}' > sla_wrappers.c && \
    gcc -c -O2 -fPIC sla_wrappers.c -I/usr/include && \
    ar rcs ${TRM_SOFTWARE}/lib/libcsla.a *.o sla_wrappers.o && \
    ranlib ${TRM_SOFTWARE}/lib/libcsla.a && \
    cp slalib.h ${TRM_SOFTWARE}/include/ && \
    sed -i '/^double slaZd/a\
\
void slaEpv(double date, double ph[3], double vh[3], double pb[3], double vb[3]);\
void slaPneqx(double date, double rnpb[3][3]);\
void slaI2o(double ri, double di, double utc, double dut, double elong, double phi, double hm, double xp, double yp, double tc, double pm, double rh, double wl, double tlr, double *aob, double *zob, double *hob, double *dob, double *rob);' ${TRM_SOFTWARE}/include/slalib.h && \
    cp slamac.h ${TRM_SOFTWARE}/include/ && \
    cd .. && rm -rf pyslalib

# -----------------------------------------------------------------------------
# Build cpp-mem (required by trm-doppler)
# -----------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/trmrsh/cpp-mem.git && \
    cd cpp-mem && \
    ./bootstrap && \
    ./configure --prefix=/opt/trm && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf cpp-mem

# -----------------------------------------------------------------------------
# Build cpp-subs (base library, required by everything else)
# Requires ERFA for modern SLALIB compatibility functions
# Copy slalib headers to standard location for autoconf
# -----------------------------------------------------------------------------
RUN cp /opt/trm/include/slalib.h /usr/include/slalib.h && \
    cp /opt/trm/include/slamac.h /usr/include/slamac.h && \
    echo '#include <slalib.h>' | g++ -E -x c++ - > /dev/null && \
    git clone --depth 1 https://github.com/trmrsh/cpp-subs.git && \
    cd cpp-subs && \
    ./bootstrap && \
    ./configure --prefix=/opt/trm \
        LDFLAGS="-L/opt/trm/lib" \
        LIBS="-lcsla -lerfa -lgfortran" && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf cpp-subs

# -----------------------------------------------------------------------------
# Build cpp-colly (molly spectra access, depends on subs)
# -----------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/trmrsh/cpp-colly.git && \
    cd cpp-colly && \
    ./bootstrap && \
    ./configure --prefix=/opt/trm \
        CPPFLAGS="-I/opt/trm/include" \
        LDFLAGS="-L/opt/trm/lib" \
        LIBS="-lsubs -lcsla -lerfa -lgfortran" && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf cpp-colly

# -----------------------------------------------------------------------------
# Build cpp-binary (binary star functions, depends on subs)
# -----------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/trmrsh/cpp-binary.git && \
    cd cpp-binary && \
    ./bootstrap && \
    ./configure --prefix=/opt/trm \
        CPPFLAGS="-I/opt/trm/include" \
        LDFLAGS="-L/opt/trm/lib" \
        LIBS="-lsubs -lcsla -lerfa -lgfortran" && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf cpp-binary

# -----------------------------------------------------------------------------
# Build cpp-roche (Roche geometry, depends on subs + binary)
# -----------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/trmrsh/cpp-roche.git && \
    cd cpp-roche && \
    ./bootstrap && \
    ./configure --prefix=/opt/trm \
        CPPFLAGS="-I/opt/trm/include" \
        LDFLAGS="-L/opt/trm/lib" \
        LIBS="-lsubs -lbinary -lcsla -lerfa -lgfortran" && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf cpp-roche

# -----------------------------------------------------------------------------
# Build cpp-lcurve (light curve modeling, depends on all above)
# -----------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/trmrsh/cpp-lcurve.git && \
    cd cpp-lcurve && \
    ./bootstrap && \
    ./configure --prefix=/opt/trm \
        CPPFLAGS="-I/opt/trm/include" \
        LDFLAGS="-L/opt/trm/lib" \
        LIBS="-lsubs -lcolly -lbinary -lroche -lcsla -lerfa -lgfortran" && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf cpp-lcurve

# =============================================================================
# Stage 2: Build Python packages
# =============================================================================
FROM python:${PYTHON_VERSION}-bookworm AS python-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libfftw3-dev \
    libgomp1 \
    libpcre3-dev \
    libpcrecpp0v5 \
    gfortran \
    git \
    && rm -rf /var/lib/apt/lists/*

ENV TRM_SOFTWARE=/opt/trm
ENV CPPFLAGS="-I${TRM_SOFTWARE}/include"
ENV LDFLAGS="-L${TRM_SOFTWARE}/lib"
ENV LD_LIBRARY_PATH="${TRM_SOFTWARE}/lib:${LD_LIBRARY_PATH}"

# Copy C++ libraries from builder
COPY --from=cpp-builder ${TRM_SOFTWARE} ${TRM_SOFTWARE}

# Install Python build dependencies
RUN pip install --no-cache-dir numpy cython

WORKDIR /build

# Build trm-subs (Python utilities, required by trm-roche) with NumPy compatibility fix
RUN git clone --depth 1 https://github.com/trmrsh/trm-subs.git && \
    cd trm-subs && \
    sed -i 's/dtype=np\.float)/dtype=float)/g' trm/subs/dvect/bug.py trm/subs/dvect/__init__.py && \
    pip install --no-cache-dir . && \
    cd .. && rm -rf trm-subs

# Build trm-doppler with NumPy compatibility fix
RUN git clone --depth 1 https://github.com/genghisken/trm-doppler.git && \
    cd trm-doppler && \
    sed -i 's/dtype=np\.int)/dtype=int)/g' trm/doppler/data.py trm/doppler/scripts/makedata.py && \
    pip install --no-cache-dir . && \
    cd .. && rm -rf trm-doppler

# Build trm-roche (Python bindings for roche)
# Use older Cython for compatibility with wildcard cimport
RUN pip install --no-cache-dir 'cython<3' && \
    git clone --depth 1 https://github.com/trmrsh/trm-roche.git && \
    cd trm-roche && \
    pip install --no-cache-dir . && \
    cd .. && rm -rf trm-roche

# =============================================================================
# Stage 3: Runtime image with Jupyter
# =============================================================================
FROM python:${PYTHON_VERSION}-slim-bookworm AS runtime

LABEL maintainer="doppler-lcurve-container"
LABEL description="TRM-Doppler and Lcurve with Jupyter Notebook support"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libfftw3-double3 \
    libgomp1 \
    libpcre3 \
    libpcrecpp0v5 \
    libpng16-16 \
    libx11-6 \
    libgfortran5 \
    liberfa1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

ENV TRM_SOFTWARE=/opt/trm
ENV LD_LIBRARY_PATH=${TRM_SOFTWARE}/lib:${LD_LIBRARY_PATH}
ENV PATH=${TRM_SOFTWARE}/bin:${PATH}
ENV PGPLOT_DIR=${TRM_SOFTWARE}/lib

# Copy C++ libraries
COPY --from=cpp-builder ${TRM_SOFTWARE} ${TRM_SOFTWARE}

# Copy Python packages from builder
COPY --from=python-builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=python-builder /usr/local/bin /usr/local/bin

# Install Jupyter and common scientific packages
RUN pip install --no-cache-dir \
    jupyterlab \
    notebook \
    astropy \
    numpy \
    scipy \
    matplotlib \
    ipywidgets \
    pandas \
    emcee \
    corner

# Create non-root user for security
RUN useradd -m -s /bin/bash doppler && \
    mkdir -p /home/doppler/workspace /home/doppler/software && \
    chown -R doppler:doppler /home/doppler

USER doppler
WORKDIR /home/doppler/workspace

# Jupyter configuration (can be overridden via docker-compose)
ENV JUPYTER_PORT=8888

EXPOSE ${JUPYTER_PORT}

# Default command: start Jupyter Lab
CMD sh -c "jupyter lab --ip=0.0.0.0 --port=${JUPYTER_PORT} --no-browser --NotebookApp.token='' --NotebookApp.password=''"

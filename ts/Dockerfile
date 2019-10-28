# Build Task Spooler binary in container b/c gridftp doesn't have a build environment
# http://vicerveza.homeunix.net/~viric/soft/ts/
FROM centos:6

# Latest updates and build environment
RUN yum -y update && \
    yum -y install gcc

# Download source and build executable
RUN mkdir /tmp/build && \
    cd /tmp/build && \
    curl -O http://vicerveza.homeunix.net/~viric/soft/ts/ts-1.0.tar.gz && \
    tar xzf ts-1.0.tar.gz && \
    cd ts-1.0 && \
    make && \
    make install

WORKDIR /app
RUN cp /usr/local/bin/ts . && \
    cp /usr/local/share/man/man1/ts.1 .

# TODO  Get executable and man page into host filesystem

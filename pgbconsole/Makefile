PROGRAM_NAME = pgbconsole
SOURCE = pgbconsole.c
CC = gcc
CFLAGS = -O2 -g -Wall
PREFIX = /usr
PGLIBDIR = $(shell pg_config --libdir)
PGINCLUDEDIR = $(shell pg_config --includedir)
LIBS = -lncurses -lpq

.PHONY: all clean install

all: pgbconsole

pgbconsole: pgbconsole.c
	gcc $(CFLAGS) -I$(PGINCLUDEDIR) -L$(PGLIBDIR) -o $(PROGRAM_NAME) $(SOURCE) $(LIBS)

clean:
	rm -f $(PROGRAM_NAME)

install:
	install -s $(PROGRAM_NAME) $(PREFIX)/bin

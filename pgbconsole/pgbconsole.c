/*
 * pgbconsole: top-like console for Pgbouncer - PostgreSQL connection pooler.
 * (C) 2015 by Alexey V. Lesovsky (lesovsky <at> gmail.com)
 */

#include <arpa/inet.h>
#include <errno.h>
#include <getopt.h>
#include <ifaddrs.h>
#include <linux/if_link.h>
#include <limits.h>
#include <ncurses.h>
#include <netdb.h>
#include <pwd.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include "libpq-fe.h"
#include "pgbconsole.h"

/*
 ******************************************************** routine function **
 * Trap keys in program main mode
 *
 * RETURNS:
 * 1 if key is pressed or 0 if not.
 ****************************************************************************
 */
int key_is_pressed(void)
{
    int ch = getch();
    if (ch != ERR) {
        ungetch(ch);
        return 1;
    }
    else
        return 0;
}
    
/*
 *********************************************************** init function **
 * Allocate memory for connections options struct array
 *
 * OUT:
 * @conn_opts   Initialized array of connection options
 ****************************************************************************
 */
void init_conn_opts(struct conn_opts_struct *conn_opts[])
{
    int i;
    for (i = 0; i < MAX_CONSOLE; i++) {
        if ((conn_opts[i] = (struct conn_opts_struct *)
                    malloc(CONN_OPTS_SIZE)) == NULL) {
            perror("malloc");
            exit(EXIT_FAILURE);
        }
        memset(conn_opts[i], 0, CONN_OPTS_SIZE);
        conn_opts[i]->terminal = i;
        conn_opts[i]->conn_used = false;
        strcpy(conn_opts[i]->host, "");
        strcpy(conn_opts[i]->port, "");
        strcpy(conn_opts[i]->user, "");
        strcpy(conn_opts[i]->dbname, "");
        strcpy(conn_opts[i]->password, "");
        strcpy(conn_opts[i]->conninfo, "");
        conn_opts[i]->log_opened = false;
    }
}

/*
 ******************************************************** startup function **
 * Take input parameters and add them into connections options.
 *
 * IN:
 * @argc            Input arguments count.
 * @argv[]          Input arguments array.
 *
 * OUT:
 * @conn_opts[]     Array where connections options will be saved.
 ****************************************************************************
 */
void create_initial_conn(int argc, char *argv[],
        struct conn_opts_struct * conn_opts[])
{
    struct passwd *pw = getpwuid(getuid());

    /* short options */
    const char * short_options = "h:p:U:d:wW?";

    /* long options */
    const struct option long_options[] = {
        {"help", no_argument, NULL, '?'},
        {"host", required_argument, NULL, 'h'},
        {"port", required_argument, NULL, 'p'},
        {"dbname", required_argument, NULL, 'd'},
        {"no-password", no_argument, NULL, 'w'},
        {"password", no_argument, NULL, 'W'},
        {"user", required_argument, NULL, 'U'},
        {NULL, 0, NULL, 0}
    };

    int param, option_index;
    enum trivalue prompt_password = TRI_DEFAULT;

    if (argc > 1)
    {
        if ((strcmp(argv[1], "-?") == 0)
                || (argc == 2 && (strcmp(argv[1], "--help") == 0)))
        {
            print_usage();
            exit(EXIT_SUCCESS);
        }
        if (strcmp(argv[1], "--version") == 0
                || strcmp(argv[1], "-V") == 0)
        {
            printf("  %s, version %.1f (%s)\n", PROGRAM_NAME, PROGRAM_VERSION, PROGRAM_RELEASE);
            exit(EXIT_SUCCESS);
        }
    }

    while ( (param = getopt_long(argc, argv,
                    short_options, long_options, &option_index)) != -1 )
    {
        switch(param)
        {
            case 'h':
                strcpy(conn_opts[0]->host, optarg);
                break;
            case 'p':
                strcpy(conn_opts[0]->port, optarg);
                break;
            case 'U':
                strcpy(conn_opts[0]->user, optarg);
                break;
            case 'd':
                strcpy(conn_opts[0]->dbname, optarg);
                break;
            case 'w':
                prompt_password = TRI_NO;
                break;
            case 'W':
                prompt_password = TRI_YES;
                break;
            case '?': default:
                fprintf(stderr,
                        "Try \"%s --help\" for more information.\n", argv[0]);
                exit (EXIT_SUCCESS);
                break;
        }
    }

    while (argc - optind >= 1)
    {
        if ( (argc - optind > 1)
                && strlen(conn_opts[0]->user) == 0
                && strlen(conn_opts[0]->dbname) == 0 )
            strcpy(conn_opts[0]->user, argv[optind]);
        else if ( (argc - optind >= 1) && strlen(conn_opts[0]->dbname) == 0 )
            strcpy(conn_opts[0]->dbname, argv[optind]);
        else
            fprintf(stderr,
                    "%s: warning: extra command-line argument \"%s\" ignored\n",
                    argv[0], argv[optind]);
        optind++;
    }

    if ( strlen(conn_opts[0]->host) == 0 )
        strcpy(conn_opts[0]->host, DEFAULT_HOST);

    if ( strlen(conn_opts[0]->port) == 0 )
        strcpy(conn_opts[0]->port, DEFAULT_PORT);

    if ( strlen(conn_opts[0]->user) == 0 ) {
        strcpy(conn_opts[0]->user, pw->pw_name);
    }

    if ( prompt_password == TRI_YES )
        strcpy(conn_opts[0]->password, password_prompt("Password: ", 100, false));

    if ( strlen(conn_opts[0]->dbname) == 0
            && strlen(conn_opts[0]->user) == 0 ) {
        strcpy(conn_opts[0]->user, pw->pw_name);
        strcpy(conn_opts[0]->dbname, DEFAULT_DBNAME);
    }
    else if ( strlen(conn_opts[0]->user) != 0
            && strlen(conn_opts[0]->dbname) == 0 )
        strcpy(conn_opts[0]->dbname, conn_opts[0]->user);

    conn_opts[0]->conn_used = true;
}

/*
 ******************************************************** startup function **
 * Print usage.
 ****************************************************************************
 */
void print_usage(void)
{
    printf("%s is the top-like interactive console for Pgbouncer.\n\n", PROGRAM_NAME);
    printf("Usage:\n \
  %s [OPTION]... [DBNAME [USERNAME]]\n\n", PROGRAM_NAME);
    printf("General options:\n \
  -?, --help                show this help, then exit.\n \
  -V, --version             print version, then exit.\n\n");
    printf("Options:\n \
  -h, --host=HOSTNAME       pgbouncer server host or socket directory (default: \"/tmp\")\n \
  -p, --port=PORT           pgbouncer server port (default: \"6432\")\n \
  -U, --username=USERNAME   pgbouncer admin user name (default: \"current logged user\")\n \
  -d, --dbname=DBNAME       pgbouncer admin database name (default: \"pgbouncer\")\n \
  -w, --no-password         never prompt for password\n \
  -W, --password            force password prompt (should happen automatically)\n\n");
    printf("Report bugs to %s.\n", PROGRAM_AUTHORS_CONTACTS);
}

/*
 ******************************************************** startup function **
 * Read ~/.pgbrc file and fill up connections options array.
 *
 * IN:
 * @argc            Input arguments count.
 * @argv[]          Input arguments array.
 * @pos             Start position inside array.
 *
 * OUT:
 * @conn_opts       Connections options array.
 *
 * RETURNS:
 * Success or failure.
 ****************************************************************************
 */
int create_pgbrc_conn(int argc, char *argv[],
        struct conn_opts_struct * conn_opts[], const int pos)
{
    FILE *fp;
    static char pgbrcpath[PATH_MAX];
    struct stat statbuf;
    char strbuf[BUFFERSIZE];
    int i = pos;
    struct passwd *pw = getpwuid(getuid());

    strcpy(pgbrcpath, pw->pw_dir);
    strcat(pgbrcpath, "/");
    strcat(pgbrcpath, PGBRC_FILE);

    if (access(pgbrcpath, F_OK) == -1) {
        return PGBRC_READ_ERR;
    }

    stat(pgbrcpath, &statbuf);
    if ( statbuf.st_mode & (S_IRWXG | S_IRWXO) ) {
        fprintf(stderr,
                "WARNING: %s has wrong permissions.\n", pgbrcpath);
        return PGBRC_READ_ERR;
    }

    /* read connections settings from .pgbrc */
    if ((fp = fopen(pgbrcpath, "r")) != NULL) {
        while (fgets(strbuf, 4096, fp) != 0) {
            sscanf(strbuf, "%[^:]:%[^:]:%[^:]:%[^:]:%[^:\n]",
                conn_opts[i]->host, conn_opts[i]->port,
                conn_opts[i]->dbname,   conn_opts[i]->user,
                conn_opts[i]->password);
            conn_opts[i]->terminal = i;
            conn_opts[i]->conn_used = true;
            i++;
        }
        fclose(fp);
        return PGBRC_READ_OK;
    } else {
        fprintf(stdout,
                "WARNING: failed to open %s. Try use defaults.\n", pgbrcpath);
        return PGBRC_READ_ERR;
    }
}

/*
 ******************************************************** startup function **
 * Prepare conninfo string for PQconnectdb.
 *
 * IN:
 * @conn_opts       Connections options array without filled conninfo.
 *
 * OUT:
 * @conn_opts       Connections options array with conninfo.
 ****************************************************************************
 */
void prepare_conninfo(struct conn_opts_struct * conn_opts[])
{
    int i;
    for ( i = 0; i < MAX_CONSOLE; i++ )
        if (conn_opts[i]->conn_used) {
            strcat(conn_opts[i]->conninfo, "host=");
            strcat(conn_opts[i]->conninfo, conn_opts[i]->host);
            strcat(conn_opts[i]->conninfo, " port=");
            strcat(conn_opts[i]->conninfo, conn_opts[i]->port);
            strcat(conn_opts[i]->conninfo, " user=");
            strcat(conn_opts[i]->conninfo, conn_opts[i]->user);
            strcat(conn_opts[i]->conninfo, " dbname=");
            strcat(conn_opts[i]->conninfo, conn_opts[i]->dbname);
            if ((strlen(conn_opts[i]->password)) != 0) {
                strcat(conn_opts[i]->conninfo, " password=");
                strcat(conn_opts[i]->conninfo, conn_opts[i]->password);
            }
        }
}

/*
 ******************************************************** startup function **
 * Open connections to pgbouncer using conninfo string from conn_opts.
 *
 * IN:
 * @conn_opts       Connections options array.
 *
 * OUT:
 * @conns           Array of connections.
 ****************************************************************************
 */
void open_connections(struct conn_opts_struct * conn_opts[], PGconn * conns[])
{
    int i;
    for ( i = 0; i < MAX_CONSOLE; i++ ) {
        if (conn_opts[i]->conn_used) {
            conns[i] = PQconnectdb(conn_opts[i]->conninfo);
            if ( PQstatus(conns[i]) == CONNECTION_BAD && PQconnectionNeedsPassword(conns[i]) == 1) {
                printf("%s:%s %s@%s require ", 
                        conn_opts[i]->host, conn_opts[i]->port,
                        conn_opts[i]->user, conn_opts[i]->dbname);
                strcpy(conn_opts[i]->password, password_prompt("password: ", 100, false));
                strcat(conn_opts[i]->conninfo, " password=");
                strcat(conn_opts[i]->conninfo, conn_opts[i]->password);
                conns[i] = PQconnectdb(conn_opts[i]->conninfo);
            } else if ( PQstatus(conns[i]) == CONNECTION_BAD ) {
                printf("Unable to connect to %s:%s %s@%s",
                        conn_opts[i]->host, conn_opts[i]->port,
                        conn_opts[i]->user, conn_opts[i]->dbname);
            }
        }
    }
}

/*
 ****************************************************** key press function **
 * Open new one connection.
 *
 * IN:
 * @window          Window where result is printed.
 * @conn_opts       Connections options array.
 *
 * OUT:
 * @conns           Array of connections.
 * @conn_opts       Connections options array.
 *
 * RETURNS:
 * Add connection into conns array and return new console index.
 ****************************************************************************
 */
int add_connection(WINDOW * window, struct conn_opts_struct * conn_opts[],
        PGconn * conns[], int console_index)
{
    int i;
    char params[128];
    bool * with_esc = (bool *) malloc(sizeof(bool)),
         * with_esc2 = (bool *) malloc(sizeof(bool));
    char * str = (char *) malloc(sizeof(char) * 128),
         * str2 = (char *) malloc(sizeof(char) * 128);

    echo();
    cbreak();
    nodelay(window, FALSE);
    keypad(window, TRUE);

    for (i = 0; i < MAX_CONSOLE; i++) {
        if (conn_opts[i]->conn_used == false) {
            wprintw(window, "Enter new connection parameters, format \"host port username dbname\": ");
            wrefresh(window);

            cmd_readline(window, 69, with_esc, str);
            strcpy(params, str);
            free(str);
            if (strlen(params) != 0 && *with_esc == false) {
                sscanf(params, "%s %s %s %s",
                    conn_opts[i]->host,    conn_opts[i]->port,
                    conn_opts[i]->user,        conn_opts[i]->dbname);
                conn_opts[i]->conn_used = true;
                strcat(conn_opts[i]->conninfo, "host=");
                strcat(conn_opts[i]->conninfo, conn_opts[i]->host);
                strcat(conn_opts[i]->conninfo, " port=");
                strcat(conn_opts[i]->conninfo, conn_opts[i]->port);
                strcat(conn_opts[i]->conninfo, " user=");
                strcat(conn_opts[i]->conninfo, conn_opts[i]->user);
                strcat(conn_opts[i]->conninfo, " dbname=");
                strcat(conn_opts[i]->conninfo, conn_opts[i]->dbname);

                conns[i] = PQconnectdb(conn_opts[i]->conninfo);
                if ( PQstatus(conns[i]) == CONNECTION_BAD && PQconnectionNeedsPassword(conns[i]) == 1) {
                    PQfinish(conns[i]);
                    noecho();
                    nodelay(window, FALSE);
                    wclear(window);
                    wprintw(window, "Required password: ");
                    wrefresh(window);
                    cmd_readline(window, 19, with_esc2, str2);

                    if (strlen(str2) != 0 && *with_esc2 == false) {
                        strcpy(conn_opts[i]->password, str2);
                        strcat(conn_opts[i]->conninfo, " password=");
                        strcat(conn_opts[i]->conninfo, conn_opts[i]->password);
                        conns[i] = PQconnectdb(conn_opts[i]->conninfo);
                        if ( PQstatus(conns[i]) == CONNECTION_BAD ) {
                            wclear(window);
                            wprintw(window, "Unable to connect to the pgbouncer.");
                            PQfinish(conns[i]);
                            clear_conn_opts(conn_opts, i);
                        } else {
                            wclear(window);
                            wprintw(window, "Successfully connected.");
                            console_index = conn_opts[i]->terminal;
                        }
                    } else if (with_esc) {
                        clear_conn_opts(conn_opts, i);
                    }
                    free(str2);
                }
                else {
                    wclear(window);
                    wprintw(window, "Successfully connected.");
                    console_index = conn_opts[i]->terminal;
                }
                break;
            } else if (strlen(params) == 0 && *with_esc == false) {
                wprintw(window, "Nothing to do.");
                break;
            } else 
                break;
        } else if (i == MAX_CONSOLE - 1) {
            wprintw(window, "No free consoles.");
        }
    }

    free(with_esc);
    free(with_esc2);
    noecho();
    cbreak();
    nodelay(window, TRUE);
    keypad(window, FALSE);

    return console_index;
}

/*
 ******************************************************** routine function **
 * Clear single connection options.
 *
 * IN:
 * @conn_opts       Connections options array.
 * @i               Index of entry in conn_opts array which should cleared.
 ****************************************************************************
 */
void clear_conn_opts(struct conn_opts_struct * conn_opts[], int i)
{
    strcpy(conn_opts[i]->host, "");
    strcpy(conn_opts[i]->port, "");
    strcpy(conn_opts[i]->user, "");
    strcpy(conn_opts[i]->dbname, "");
    strcpy(conn_opts[i]->password, "");
    strcpy(conn_opts[i]->conninfo, "");
    conn_opts[i]->conn_used = false;
}

/*
 ******************************************************** routine function **
 * Shift consoles when current console closes.
 *
 * IN:
 * @conn_opts       Connections options array.
 * @conns           Connections array.
 * @i               Index of closed console.
 *
 * RETURNS:
 * Array of conn_opts without closed connection.
 ****************************************************************************
 */
void shift_consoles(struct conn_opts_struct * conn_opts[], PGconn * conns[], int i)
{
    while (conn_opts[i + 1]->conn_used != false) {
        strcpy(conn_opts[i]->host,      conn_opts[i + 1]->host);
        strcpy(conn_opts[i]->port,      conn_opts[i + 1]->port);
        strcpy(conn_opts[i]->user,      conn_opts[i + 1]->user);
        strcpy(conn_opts[i]->dbname,    conn_opts[i + 1]->dbname);
        strcpy(conn_opts[i]->password,  conn_opts[i + 1]->password);
        conns[i] = conns[i + 1];
        i++;
        if (i == MAX_CONSOLE - 1)
            break;
    }
    clear_conn_opts(conn_opts, i);
}

/*
 ***************************************************** key press functions **
 * Close current connection.
 *
 * IN:
 * @window          Window where result is printed.
 * @conn_opts       Connections options array.
 *
 * OUT:
 * @conns           Array of connections.
 * @conn_opts       Connections options array.
 *
 * RETURNS:
 * Close current connection (remove from conns array) and return prvious
 * console index.
 ****************************************************************************
 */
int close_connection(WINDOW * window, struct conn_opts_struct * conn_opts[],
        PGconn * conns[], int console_index)
{
    int i = console_index;
    PQfinish(conns[console_index]);

    wprintw(window, "Close current pgbouncer connection.");
    if (i == 0) {                               // first console active
        if (conn_opts[i + 1]->conn_used) {
            shift_consoles(conn_opts, conns, i);
        } else {
            wrefresh(window);
            endwin();
            exit(EXIT_SUCCESS);
        }
    } else if (i == (MAX_CONSOLE - 1)) {        // last possible console active
        clear_conn_opts(conn_opts, i);
        console_index = console_index - 1;
    } else {                                    // in the middle console active
        if (conn_opts[i + 1]->conn_used) {
            shift_consoles(conn_opts, conns, i);
        } else {
            clear_conn_opts(conn_opts, i);
            console_index = console_index - 1;
        }
    }

    return console_index;
}

/*
 **************************************************** end program function **
 * Close connections to pgbouncers.
 *
 * IN:
 * @conns       Array of connections.
 ****************************************************************************
 */
void close_connections(struct conn_opts_struct * conn_opts[], PGconn * conns[])
{
    int i;
    for (i = 0; i < MAX_CONSOLE; i++)
        if (conn_opts[i]->conn_used)
            PQfinish(conns[i]);
}

/*
 ******************************************************** routine function **
 * Chech connection state, try reconnect if failed.
 *
 * IN:
 * @window          Window where status will be printed.
 * @conn_opts       Conn options associated with current console.
 * @conn            Connection associated with current console.
 ****************************************************************************
 */
void reconnect_if_failed(WINDOW * window, struct conn_opts_struct * conn_opts, PGconn * conn)
{
    if (PQstatus(conn) == CONNECTION_BAD) {
        wclear(window);
        PQreset(conn);
        wprintw(window,
                "The connection to the server was lost. Attempting reconnect.");
        wrefresh(window);
        sleep(1);
    } 
}

/*
 ********************************************************* routine function **
 * Send query to pgbouncer.
 *
 * IN:
 * @conn            Pgbouncer connection.
 * @query_context   Type of query.
 *
 * RETURNS:
 * Answer from pgbouncer.
 ****************************************************************************
 */
PGresult * do_query(PGconn *conn, enum context query_context)
{
    PGresult    *res;
    char query[20];
    switch (query_context) {
        case pools: default:
            strcpy(query, "show pools");
            break;
        case clients:
            strcpy(query, "show clients");
            break;
        case servers:
            strcpy(query, "show servers");
            break;
        case databases:
            strcpy(query, "show databases");
            break;
        case stats:
            strcpy(query, "show stats");
            break;
        case config:
            strcpy(query, "show config");
            break;
    }
    res = PQexec(conn, query);
    if ( PQresultStatus(res) != PG_TUP_OK ) {
        puts("We didn't get any data.");
        PQclear(res);
        return NULL;
    }
    else
        return res;
}

/*
 ******************************************************** routine function **
 * Print answer from pgbouncer to the program main window.
 *
 * IN:
 * @window              Window which is used for print.
 * @query_context       Type of query.
 * @res                 Answer from pgbouncer.
 ****************************************************************************
 */
void print_data(WINDOW * window, enum context query_context, PGresult *res)
{
    int    row_count, col_count, row, col, i;
    row_count = PQntuples(res);
    col_count = PQnfields(res);
    struct colAttrs *columns = (struct colAttrs *) malloc(sizeof(struct colAttrs) * col_count);

    columns = calculate_width(columns, row_count, col_count, res);
    wclear(window);
    /* print column names */
    wattron(window, A_BOLD);
    for ( col = 0, i = 0; col < col_count; col++, i++ )
        wprintw(window, "%-*s", columns[i].width, PQfname(res,col));
    wprintw(window, "\n");
    wattroff(window, A_BOLD);
    /* print rows */
    for ( row = 0; row < row_count; row++ ) {
        for ( col = 0, i = 0; col < col_count; col++, i++ ) {
            wprintw(window,
                    "%-*s", columns[i].width, PQgetvalue(res, row, col));
        }
    wprintw(window, "\n");
    }
    wprintw(window, "\n");
    wrefresh(window);

    PQclear(res);
    free(columns);
}

/*
 ******************************************************** startup function **
 * Password prompt.
 *
 * IN:
 * @prompt          Text of prompt.
 * @maxlen          Length of input string.
 * @echo            Echo input string.
 *
 * RETURNS:
 * @password        Password.
 ****************************************************************************
 */
char * password_prompt(const char *prompt, int maxlen, bool echo)
{
    struct termios t_orig, t;
    char *password;
    password = (char *) malloc(maxlen + 1);

    if (!echo) {
        tcgetattr(fileno(stdin), &t);
        t_orig = t;
        t.c_lflag &= ~ECHO;
        tcsetattr(fileno(stdin), TCSAFLUSH, &t);
    }

    fputs(prompt, stdout);
    if (fgets(password, maxlen + 1, stdin) == NULL)
        password[0] = '\0';

    if (!echo) {
        tcsetattr(fileno(stdin), TCSAFLUSH, &t_orig);
        fputs("\n", stdout);
        fflush(stdout);
    }

    return password;
}

/*
 ************************************************* summary window function **
 * Print current time.
 *
 * RETURNS:
 * Return current time.
 ****************************************************************************
 */
void get_time(char * strtime)
{
    time_t rawtime;
    struct tm *timeinfo;

    time(&rawtime);
    timeinfo = localtime(&rawtime);
    strftime(strtime, 20, "%Y-%m-%d %H:%M:%S", timeinfo);
}

/*
 ************************************************* summary window function **
 * Print title into summary window: program name and current time.
 *
 * IN:
 * @window          Window where title will be printed.
 ****************************************************************************
 */
void print_title(WINDOW * window, char * progname)
{
    char *strtime = (char *) malloc(sizeof(char) * 20);
    get_time(strtime);
    wprintw(window, "%s: %s, ", progname, strtime);
    free(strtime);
}
/*
 ************************************************* summary window function **
 * Read /proc/loadavg and return load average value.
 *
 * IN:
 * @m       Minute value.
 *
 * RETURNS:
 * Load average for 1, 5 or 15 minutes.
 ****************************************************************************
 */
float get_loadavg(const int m)
{
    if ( m != 1 && m != 5 && m != 15 )
        fprintf(stderr, "invalid value for load average\n");

    float avg = 0, avg1, avg5, avg15;
    FILE *loadavg_fd;

    if ((loadavg_fd = fopen(LOADAVG_FILE, "r")) == NULL) {
        fprintf(stderr, "can't open %s\n", LOADAVG_FILE);
        exit(EXIT_FAILURE);
    } else {
        fscanf(loadavg_fd, "%f %f %f", &avg1, &avg5, &avg15);
        fclose(loadavg_fd);
    }

    switch (m) {
        case 1: avg = avg1; break;
        case 5: avg = avg5; break;
        case 15: avg = avg15; break;
    }
    return avg;
}


/*
 ************************************************* summary window function **
 * Print load average into summary window.
 *
 * IN:
 * @window      Window where load average will be printed.
 ****************************************************************************
 */
void print_loadavg(WINDOW * window)
{
    wprintw(window, "load average: %.2f, %.2f, %.2f\n",
            get_loadavg(1),
            get_loadavg(5),
            get_loadavg(15));
}

/*
 ************************************************* summary window function **
 * Print current connection info.
 *
 * IN:
 * @window          Window where info will be printed.
 * @conn_opts       Struct with connections options.
 * @conn            Current connection.
 * @console_no      Current console number.
 ****************************************************************************
 */
void print_conninfo(WINDOW * window, struct conn_opts_struct * conn_opts, PGconn *conn, int console_no)
{
    static char state[8];
    switch (PQstatus(conn)) {
        case CONNECTION_OK:
            strcpy(state, "ok");
            break;
        case CONNECTION_BAD:
            strcpy(state, "failed");
            break;
        default:
            strcpy(state, "unknown");
            break;
    }
        wprintw(window, " console %i: %s:%s %s@%s\t connection state: %s\n",
            console_no,
            conn_opts->host, conn_opts->port,
            conn_opts->user, conn_opts->dbname,
            state);
}

/*
 **************************************************** get cpu stat function **
 * Allocate memory for cpu statistics struct.
 *
 * OUT:
 * @st_cpu      Struct for cpu statistics.
 ****************************************************************************
 */
void init_stats(struct stats_cpu_struct *st_cpu[])
{
    int i;
    /* Allocate structures for CPUs "all" and 0 */
    for (i = 0; i < 2; i++) {
        if ((st_cpu[i] = (struct stats_cpu_struct *) 
                    malloc(STATS_CPU_SIZE * 2)) == NULL) {
            perror("malloc");
            exit(EXIT_FAILURE);
        }
        memset(st_cpu[i], 0, STATS_CPU_SIZE * 2);
    }
}

/*
 *************************************************** get cpu stat function **
 * Get system clock resolution.
 *
 * OUT:
 * @hz      Number of intervals per second.
 ****************************************************************************
 */
void get_HZ(void)
{
        long ticks;

        if ((ticks = sysconf(_SC_CLK_TCK)) == -1) {
                perror("sysconf");
        }

        hz = (unsigned int) ticks;
}

/*
 *************************************************** get cpu stat function **
 * Read machine uptime independently of the number of processors.
 *
 * OUT:
 * @uptime          Uptime value in jiffies.
 ****************************************************************************
 */
void read_uptime(unsigned long long *uptime)
{
        FILE *fp;
        char line[128];
        unsigned long up_sec, up_cent;

        if ((fp = fopen(UPTIME_FILE, "r")) == NULL)
                return;

        if (fgets(line, sizeof(line), fp) == NULL) {
                fclose(fp);
                return;
        }

        sscanf(line, "%lu.%lu", &up_sec, &up_cent);
        *uptime = (unsigned long long) up_sec * HZ +
                  (unsigned long long) up_cent * HZ / 100;
        fclose(fp);
}

/*
 *************************************************** get cpu stat function **
 * Read cpu statistics from /proc/stat. Also calculate uptime if 
 * read_uptime() function return NULL.
 *
 * IN:
 * @st_cpu          Struct where stat will be saved.
 * @nbr             Total number of CPU (including cpu "all").
 *
 * OUT:
 * @st_cpu          Struct with statistics.
 * @uptime          Machine uptime multiplied by the number of processors.
 * @uptime0         Machine uptime. Filled only if previously set to zero.
 ****************************************************************************
 */
void read_cpu_stat(struct stats_cpu_struct *st_cpu, int nbr,
                    unsigned long long *uptime, unsigned long long *uptime0)
{
    FILE *stat_fp;
    struct stats_cpu_struct *st_cpu_i;
    struct stats_cpu_struct sc;
    char line[8192];
    int proc_nb;

    if ((stat_fp = fopen(STAT_FILE, "r")) == NULL) {
        fprintf(stderr,
                "Cannot open %s: %s\n", STAT_FILE, strerror(errno));
        exit(EXIT_FAILURE);
    }

    while ( (fgets(line, sizeof(line), stat_fp)) != NULL ) {
        if (!strncmp(line, "cpu ", 4)) {
            memset(st_cpu, 0, STATS_CPU_SIZE);
            sscanf(line + 5, 
                    "%llu %llu %llu %llu %llu %llu %llu %llu %llu %llu",
                &st_cpu->cpu_user,      &st_cpu->cpu_nice,
                &st_cpu->cpu_sys,       &st_cpu->cpu_idle,
                &st_cpu->cpu_iowait,    &st_cpu->cpu_steal,
                &st_cpu->cpu_hardirq,   &st_cpu->cpu_softirq,
                &st_cpu->cpu_guest,     &st_cpu->cpu_guest_nice);
                *uptime = st_cpu->cpu_user + st_cpu->cpu_nice +
                    st_cpu->cpu_sys + st_cpu->cpu_idle +
                    st_cpu->cpu_iowait + st_cpu->cpu_steal +
                    st_cpu->cpu_hardirq + st_cpu->cpu_softirq +
                    st_cpu->cpu_guest + st_cpu->cpu_guest_nice;

        } else if (!strncmp(line, "cpu", 3)) {
            if (nbr > 1) {
                memset(&sc, 0, STATS_CPU_SIZE);
                sscanf(line + 3,
                        "%d %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu",
                    &proc_nb,           &sc.cpu_user,
                    &sc.cpu_nice,       &sc.cpu_sys,
                    &sc.cpu_idle,       &sc.cpu_iowait,
                    &sc.cpu_steal,      &sc.cpu_hardirq,
                    &sc.cpu_softirq,    &sc.cpu_guest,
                    &sc.cpu_guest_nice);

                    if (proc_nb < (nbr - 1)) {
                        st_cpu_i = st_cpu + proc_nb + 1;
                        *st_cpu_i = sc;
                    }

                    if (!proc_nb && !*uptime0) {
                        *uptime0 = sc.cpu_user + sc.cpu_nice   +
                                sc.cpu_sys     + sc.cpu_idle   +
                                sc.cpu_iowait  + sc.cpu_steal  +
                                sc.cpu_hardirq + sc.cpu_softirq;
                        printf("read_cpu_stat: uptime0 = %llu\n", *uptime0);
                    }
            }
        } 
    }
    fclose(stat_fp);
}

/*
 *************************************************** get cpu stat function **
 * Compute time interval.
 *
 * IN:
 * @prev_uptime     Previous uptime value in jiffies.
 * @curr_interval   Current uptime value in jiffies.
 *
 * RETURNS:
 * Interval of time in jiffies.
 ****************************************************************************
 */
unsigned long long get_interval(unsigned long long prev_uptime,
                                unsigned long long curr_uptime)
{
        unsigned long long itv;

        /* first run prev_uptime=0 so displaying stats since system startup */
        itv = curr_uptime - prev_uptime;

        if (!itv) {     /* Paranoia checking */
                itv = 1;
        }

        return itv;
}

/*
 *************************************************** get cpu stat function **
 * Workaround for CPU counters read from /proc/stat: Dyn-tick kernels
 * have a race issue that can make those counters go backward.
 ****************************************************************************
 */
double ll_sp_value(unsigned long long value1, unsigned long long value2,
        unsigned long long itv)
{
        if (value2 < value1)
                return (double) 0;
        else
                return SP_VALUE(value1, value2, itv);
}

/*
 *************************************************** get cpu stat function **
 * Display cpu statistics in specified window.
 *
 * IN:
 * @window      Window in which spu statistics will be printed.
 * @st_cpu      Struct with cpu statistics.
 * @curr        Index in array for current sample statistics.
 * @itv         Interval of time.
 ****************************************************************************
 */
void write_cpu_stat_raw(WINDOW * window, struct stats_cpu_struct *st_cpu[],
        int curr, unsigned long long itv)
{
        wprintw(window, 
                "      %%cpu: %4.1f us, %4.1f sy, %4.1f ni, %4.1f id, %4.1f wa, %4.1f hi, %4.1f si, %4.1f st\n",
               ll_sp_value(st_cpu[!curr]->cpu_user, st_cpu[curr]->cpu_user, itv),
               ll_sp_value(st_cpu[!curr]->cpu_sys + st_cpu[!curr]->cpu_softirq + st_cpu[!curr]->cpu_hardirq,
                           st_cpu[curr]->cpu_sys + st_cpu[curr]->cpu_softirq + st_cpu[curr]->cpu_hardirq, itv),
               ll_sp_value(st_cpu[!curr]->cpu_nice, st_cpu[curr]->cpu_nice, itv),
               (st_cpu[curr]->cpu_idle < st_cpu[!curr]->cpu_idle) ?
               0.0 :
               ll_sp_value(st_cpu[!curr]->cpu_idle, st_cpu[curr]->cpu_idle, itv),
               ll_sp_value(st_cpu[!curr]->cpu_iowait, st_cpu[curr]->cpu_iowait, itv),
               ll_sp_value(st_cpu[!curr]->cpu_hardirq, st_cpu[curr]->cpu_hardirq, itv),
               ll_sp_value(st_cpu[!curr]->cpu_softirq, st_cpu[curr]->cpu_softirq, itv),
               ll_sp_value(st_cpu[!curr]->cpu_steal, st_cpu[curr]->cpu_steal, itv));
        wrefresh(window);
}

/*
 ************************************************* summary window function **
 * Composite function which read cpu stats and uptime then print out stats 
 * to specified window.
 *
 * IN:
 * @window      Window where spu statistics will be printed.
 * @st_cpu      Struct with cpu statistics.
 ****************************************************************************
 */
void print_cpu_usage(WINDOW * window, struct stats_cpu_struct *st_cpu[])
{
    static unsigned long long uptime[2]  = {0, 0};
    static unsigned long long uptime0[2] = {0, 0};
    static int curr = 1;
    static unsigned long long itv;

    uptime0[curr] = 0;
    read_uptime(&(uptime0[curr]));
    read_cpu_stat(st_cpu[curr], 2, &(uptime[curr]), &(uptime0[curr]));
    itv = get_interval(uptime[!curr], uptime[curr]);
    write_cpu_stat_raw(window, st_cpu, curr, itv);
    itv = get_interval(uptime0[!curr], uptime0[curr]);
    curr ^= 1;
}

/*
 ************************************************* sumamry window function **
 * Print current pgbouncer summary info: total clients, servers, etc.
 *
 * IN:
 * @window          Window where info will be printed.
 * @conn            Current pgbouncer connection.
 ****************************************************************************
 */
void print_pgbouncer_summary(WINDOW * window, PGconn *conn)
{
    int cl_count, sv_count, pl_count, db_count;
    enum context query_context;
    PGresult *res;

    query_context = pools;
    res = do_query(conn, query_context);
    pl_count = PQntuples(res);
    PQclear(res);

    query_context = databases;
    res = do_query(conn, query_context);
    db_count = PQntuples(res);
    PQclear(res);

    query_context = clients;
    res = do_query(conn, query_context);
    cl_count = PQntuples(res);
    PQclear(res);

    query_context = servers;
    res = do_query(conn, query_context);
    sv_count = PQntuples(res);
    PQclear(res);

    wprintw(window,
            " pgbouncer: pools: %-5i databases: %-5i clients: %-5i servers: %-5i\n",
            pl_count, db_count, cl_count, sv_count);
}

/*
 ****************************************************** key press function **
 * Switch console using specified number.
 *
 * IN:
 * @window          Window where cmd status will be written.
 * @conn_opts[]     Struct with connections options.
 * @ch              Intercepted key (number from 1 to 8).
 * @console_no      Active console number.
 * @console_index   Index of active console.
 *
 * RETURNS:
 * Index console on which performed switching.
 ****************************************************************************
 */
int switch_conn(WINDOW * window, struct conn_opts_struct * conn_opts[],
        int ch, int console_index, int console_no)
{
    if ( conn_opts[ch - '0' - 1]->conn_used ) {
        console_no = ch - '0', console_index = console_no - 1;
        wprintw(window,
                "Switch to another pgbouncer connection (console %i)",
                console_no);
    } else
        wprintw(window,
                "Do not switch because no connection associated (stay on console %i)",
                console_no);
    return console_index;
}

/*
 ***************************************************** cmd window function **
 * Read input from cmd window.
 *
 * IN:
 * @window          Window where pause status will be printed.
 * @pos             When you delete wrong input, cursor do not moving beyond.
 *
 * OUT:
 * @with_esc        Flag which determines when function finish with ESC.
 *
 * RETURNS:
 * Pointer to the input string.
 ****************************************************************************
 */
void cmd_readline(WINDOW *window, int pos, bool * with_esc, char * str)
{
    int ch;
    int i = 0;

    while ((ch = wgetch(window)) != ERR ) {
        if (ch == 27) {
            wclear(window);
            wprintw(window, "Do nothing. Operation canceled. ");
            nodelay(window, TRUE);
            *with_esc = true;              // Finish with ESC.
            strcpy(str, "");
            return;
        } else if (ch == 10) {
            str[i] = '\0';
            nodelay(window, TRUE);
            *with_esc = false;              // Normal finish with Newline.
            return;
        } else if (ch == KEY_BACKSPACE || ch == KEY_DC || ch == 127) {
            if (i > 0) {
                i--;
                wdelch(window);
            } else {
                wmove(window, 0, pos);
                continue;
            }
        } else {
            str[i] = ch;
            i++;
        }
    }
}

/*
 ********************************************* Pgbouncer actions functions **
 * Reload pgbouncer. The PgBouncer process will reload its configuration file 
 * and update changeable settings.
 *
 * IN:
 * @window          Window where reload status will be printed.
 * @conn            Current pgbouncer connection.
 ****************************************************************************
 */
void do_reload(WINDOW * window, PGconn * conn)
{
    PGresult * res;
    res = PQexec(conn, "RELOAD");
    if (PQresultStatus(res) != PG_CMD_OK)
        wprintw(window, "Reload current pgbouncer: failed.");
    else 
        wprintw(window, "Reload current pgbouncer: success.");
    PQclear(res);
}

/*
 ********************************************* Pgbouncer actions functions **
 * Suspend pgbouncer. All socket buffers are flushed and PgBouncer stops 
 * listening for data on them. The command will not return before all buffers
 * are empty. To be used at the time of PgBouncer online reboot.
 *
 * IN:
 * @window          Window where suspend status will be printed.
 * @conn            Current pgbouncer connection.
 ****************************************************************************
 */
void do_suspend(WINDOW * window, PGconn * conn)
{
    PGresult *res;
    res = PQexec(conn, "SUSPEND");
    if (PQresultStatus(res) != PG_CMD_OK)
        wprintw(window, "Suspend current pgbouncer: %s", PQresultErrorMessage(res));
    else 
        wprintw(window, "Suspend current pgbouncer: success.");
    PQclear(res);
}

/*
 ********************************************* Pgbouncer actions functions **
 * Pause pgbouncer. PgBouncer tries to disconnect from all servers, first 
 * waiting for all queries to complete. The command will not return before all
 * queries are finished.
 *
 * IN:
 * @window          Window where pause status will be printed.
 * @conn            Current pgbouncer connection.
 ****************************************************************************
 */
void do_pause(WINDOW * window, PGconn * conn)
{
    PGresult *res;
    char query[128] = "PAUSE";
    char dbname[128];
    bool * with_esc = (bool *) malloc(sizeof(bool));
    char * str = (char *) malloc(sizeof(char) * 128);

    echo();
    cbreak();
    nodelay(window, FALSE);
    keypad(window, TRUE);

    wprintw(window, "Database to pause [default database = all] ");
    wrefresh(window);

    cmd_readline(window, 43, with_esc, str);
    strcpy(dbname, str);
    free(str);
    if (strlen(dbname) != 0 && *with_esc == false) {
        strcat(query, " ");
        strcat(query, dbname);
        res = PQexec(conn, query);
        if (PQresultStatus(res) != PG_CMD_OK)
            wprintw(window, "Pause pool %s: %s",
                    dbname, PQresultErrorMessage(res));
        else
                wprintw(window, "Pause pool %s: success.", dbname);
        PQclear(res);
    } else if (strlen(dbname) == 0 && *with_esc == false ) {
        res = PQexec(conn, query);
        if (PQresultStatus(res) != PG_CMD_OK)
            wprintw(window, "Pause pool: %s",
                    PQresultErrorMessage(res));
        else
                wprintw(window, "All pools paused");
        PQclear(res);
    }

    free(with_esc);
    noecho();
    cbreak();
    nodelay(window, TRUE);
    keypad(window, FALSE);
}

/*
 ********************************************* Pgbouncer actions functions **
 * Kill pgbouncer. Immediately drop all client and server connections on 
 * given database.
 *
 * IN:
 * @window          Window where pause status will be printed.
 * @conn            Current pgbouncer connection.
 ****************************************************************************
 */
void do_kill(WINDOW * window, PGconn * conn)
{
    PGresult *res;
    char query[128] = "KILL";
    char dbname[128];
    bool * with_esc = (bool *) malloc(sizeof(bool));
    char * str = (char *) malloc(sizeof(char) * 128);

    echo();
    cbreak();
    nodelay(window, FALSE);
    keypad(window, TRUE);

    wprintw(window, "Database to kill [must not be empty]: ");
    wrefresh(window);

    cmd_readline(window, 38, with_esc, str);
    strcpy(dbname, str);
    free(str);
    if (strlen(dbname) != 0 && *with_esc == false) {
       if (strlen(dbname) != 0) {
            strcat(query, " ");
            strcat(query, dbname);

            res = PQexec(conn, query);

            if (PQresultStatus(res) != PG_CMD_OK)
                wprintw(window, "Kill database %s: %s",
                        dbname, PQresultErrorMessage(res));
            else
                wprintw(window, "Kill database %s: success.", dbname);
            PQclear(res);
        }
    } else if (strlen(dbname) == 0 && *with_esc == false ) {
        wprintw(window, "A database is required.");
    }

    free(with_esc);
    noecho();
    cbreak();
    nodelay(window, TRUE);
    keypad(window, FALSE);
}

/*
 ********************************************* Pgbouncer actions functions **
 * Resume pgbouncer. Resume work from previous PAUSE or SUSPEND command.
 *
 * IN:
 * @window          Window where pause status will be printed.
 * @conn            Current pgbouncer connection.
 ****************************************************************************
 */
void do_resume(WINDOW * window, PGconn * conn)
{
    PGresult *res;
    char query[128] = "RESUME";
    char dbname[128];
    bool * with_esc = (bool *) malloc(sizeof(bool));
    char * str = (char *) malloc(sizeof(char) * 128);

    echo();
    cbreak();
    nodelay(window, FALSE);
    keypad(window, TRUE);

    wprintw(window, "Database to resume [default database = all] ");
    wrefresh(window);

    cmd_readline(window, 44, with_esc, str);
    strcpy(dbname, str);
    free(str);
    if (strlen(dbname) != 0 && *with_esc == false) {
        strcat(query, " ");
        strcat(query, dbname);
        res = PQexec(conn, query);
        if (PQresultStatus(res) != PG_CMD_OK)
            wprintw(window, "Resume pool %s: %s",
                    dbname, PQresultErrorMessage(res));
        else
                wprintw(window, "Resume pool %s: success.", dbname);
        PQclear(res);
    } else if (strlen(dbname) == 0 && *with_esc == false ) {
        res = PQexec(conn, query);
        if (PQresultStatus(res) != PG_CMD_OK)
            wprintw(window, "Resume pool: %s",
                    PQresultErrorMessage(res));
        else
                wprintw(window, "All pools resumed");
        PQclear(res);
    }

    free(with_esc);
    noecho();
    cbreak();
    nodelay(window, TRUE);
    keypad(window, FALSE);
}

/*
 ********************************************* Pgbouncer actions functions **
 * Shutdown pgbouncer. The PgBouncer process will exit.
 *
 * IN:
 * @window          Window where pause status will be printed.
 * @conn            Current pgbouncer connection.
 ****************************************************************************
 */
void do_shutdown(WINDOW * window, PGconn * conn)
{
    PGresult *res;
    char query[128] = "SHUTDOWN";
    char confirm[3];
    bool * with_esc = (bool *) malloc(sizeof(bool));
    char * str = (char *) malloc(sizeof(char) * 128);

    echo();
    cbreak();
    nodelay(window, FALSE);
    keypad(window, TRUE);

    wprintw(window, "Shutdown pgbouncer. Press YES to confirm. ");
    wrefresh(window);

    cmd_readline(window, 43, with_esc, str);
    strcpy(confirm, str);
    free(str);
    if (strlen(confirm) != 0 && !strcmp(confirm, "YES") && *with_esc == false) {
        res = PQexec(conn, query);
        if (PQresultStatus(res) != PG_CMD_OK)
            wprintw(window, "Pgbouncer shutdown failed with: %s",
                    PQresultErrorMessage(res));
        PQclear(res);
    } else if ((strlen(confirm) == 0 || strcmp(confirm, "YES")) && *with_esc == false ) {
            wprintw(window, "Cancel shutdown. Not confirmed.");
    }

    free(with_esc);
    noecho();
    cbreak();
    nodelay(window, TRUE);
    keypad(window, FALSE);
}

/*
 ****************************************************** key press function **
 * Write connection information into ~/.pgbrc.
 *
 * IN:
 * @window          Window where result will be printed.
 * @conn_opts       Array of connection options.
 ****************************************************************************
 */
void write_pgbrc(WINDOW * window, struct conn_opts_struct * conn_opts[])
{
    int i = 0;
    FILE *fp;
    static char pgbrcpath[PATH_MAX];
    struct passwd *pw = getpwuid(getuid());
    struct stat statbuf;

    strcpy(pgbrcpath, pw->pw_dir);
    strcat(pgbrcpath, "/");
    strcat(pgbrcpath, PGBRC_FILE);

    if ((fp = fopen(pgbrcpath, "w")) != NULL ) {
        while (conn_opts[i]->conn_used) {
            fprintf(fp, "%s:%s:%s:%s:%s\n",
                    conn_opts[i]->host,     conn_opts[i]->port,
                    conn_opts[i]->dbname,   conn_opts[i]->user,
                    conn_opts[i]->password);
            i++;
        }
        wprintw(window, "Wrote configuration to '%s'", pgbrcpath);

        fclose(fp);

        stat(pgbrcpath, &statbuf);
        if (statbuf.st_mode & (S_IRWXG | S_IRWXO)) {
            chmod(pgbrcpath, S_IRUSR|S_IWUSR);
        }
    } else {
        wprintw(window, "Failed write configuration to '%s'", pgbrcpath);
    }
}

/*
 ******************************************************** routine function **
 * Calculate column width for output data.
 *
 * IN:
 * @row_count       Number of rows in query result.
 * @col_count       Number of columns in query result.
 * @res             Query result.
 *
 * OUT:
 * @columns         Struct with column names and their max width.
 ****************************************************************************
 */
struct colAttrs * calculate_width(struct colAttrs *columns, int row_count, int col_count, PGresult *res)
{
    int i, col, row;

    for ( col = 0, i = 0; col < col_count; col++, i++) {
        strcpy(columns[i].name, PQfname(res, col));
        int colname_len = strlen(PQfname(res, col));
        int width = colname_len;
        for (row = 0; row < row_count; row++ ) {
            int val_len = strlen(PQgetvalue(res, row, col));
            if ( val_len >= width )
                width = val_len;
        }
        columns[i].width = width + 3;
    }
    return columns;
}

/*
 ****************************************************** key press function **
 * Show the current configuration settings, one per row.
 *
 * IN:
 * @conn        Current pgbouncer connection.
 *
 * RETURNS:
 * 'SHOW CONFIG' output redirected to pager (default less).
 ****************************************************************************
 */
void show_config(PGconn * conn)
{
    int  row_count, col_count, row, col, i;
    FILE *fpout;
    PGresult * res;
    struct colAttrs *columns;
    enum context query_context = config;

    res = do_query(conn, query_context);
    row_count = PQntuples(res);
    col_count = PQnfields(res);

    columns = (struct colAttrs *) malloc(sizeof(struct colAttrs) * col_count);
    columns = calculate_width(columns, row_count, col_count, res);

    fpout = popen(PAGER, "w");
    fprintf(fpout, " Pgbouncer configuration:\n");
    /* print column names */
    for (col = 0, i = 0; col < col_count; col++, i++)
        fprintf(fpout, " %-*s", columns[i].width, PQfname(res, col));
    fprintf(fpout, "\n\n");
    /* print rows */
    for (row = 0; row < row_count; row++) {
        for (col = 0, i = 0; col < col_count; col++, i++)
            fprintf(fpout, " %-*s", columns[i].width, PQgetvalue(res, row, col));
        fprintf(fpout, "\n");
    }

    PQclear(res);
    pclose(fpout);
    free(columns);
}

/*
 ******************************************************** routine function **
 * Get pgbouncer listen_address and check is that local address or not.
 *
 * IN:
 * @conn_opts       Connections options.
 *
 * RETURNS:
 * Return true if listen_address is local and false if not.
 ****************************************************************************
 */
bool check_pgb_listen_addr(struct conn_opts_struct * conn_opts)
{
    struct ifaddrs *ifaddr, *ifa;
    int family, s;
    char host[NI_MAXHOST];

    if (getifaddrs(&ifaddr) == -1) {
        freeifaddrs(ifaddr);
        return false;
    }
    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL)
            continue;

        family = ifa->ifa_addr->sa_family;

        /* Check AF_INET* interface addresses */
        if (family == AF_INET || family == AF_INET6) {
            s = getnameinfo(ifa->ifa_addr,
                            (family == AF_INET) ? sizeof(struct sockaddr_in) :
                                                  sizeof(struct sockaddr_in6),
                            host, NI_MAXHOST,
                            NULL, 0, NI_NUMERICHOST);
            if (s != 0) {
                printf("getnameinfo() failed: %s\n", gai_strerror(s));
                return false;
            }
            if (!strcmp(host, conn_opts->host) || 
                !strncmp(conn_opts->host, "/", 1)) {
                    freeifaddrs(ifaddr);
                    return true;
                    break;
            }
        }
    }

    freeifaddrs(ifaddr);
    return false;
}

/*
 ******************************************************** routine function **
 * Get log file location from pgbouncer config (show config).
 *
 * IN:
 * @conn                    Current pgboucner connection.
 * @config_option_name      Option name.
 *
 * RETURNS:
 * Returns char pointer with config option value or empty string.
 ****************************************************************************
 */
void get_conf_value(PGconn * conn, char * config_option_name, char * config_option_value)
{
    PGresult * res;
    int row_count, row;
    enum context query_context = config;

    res = do_query(conn, query_context);
    row_count = PQntuples(res);

    for (row = 0; row < row_count; row++) {
        if (!strcmp(PQgetvalue(res, row, 0), config_option_name)) {
            strcpy(config_option_value, PQgetvalue(res, row, 1));
            PQclear(res);
            return;
        }
    }

    strcpy(config_option_value, "");
    PQclear(res);
}

/*
 ****************************************************** key press function **
 * Log processing, open log in separate window or close if already opened.
 *
 * IN:
 * @window              Window where cmd status will be printed.
 * @w_log               Pointer to window where log will be shown.
 * @conn_opts           Array of connections options.
 * @conn                Current pgbouncer connection.
 ****************************************************************************
 */
void log_process(WINDOW * window, WINDOW ** w_log, struct conn_opts_struct * conn_opts, PGconn * conn)
{
    char * logfile;
    if (!conn_opts->log_opened) {
        logfile = (char *) malloc(sizeof(char) * PATH_MAX);
        if (check_pgb_listen_addr(conn_opts)) {
            *w_log = newwin(0, 0, ((LINES * 2) / 3), 0);
            wrefresh(window);
            get_conf_value(conn, PGB_CONFIG_LOGFILE, logfile);

            if (strlen(logfile) == 0) {
                wprintw(window, "Do nothing. Log file config option not found.");
                free(logfile);
                return;
            }
            if ((conn_opts->log = fopen(logfile, "r")) == NULL ) {
                wprintw(window, "Do nothing. Failed to open %s", logfile);
                free(logfile);
                return;
            }
            conn_opts->log_opened = true;
            wprintw(window, "Open current pgbouncer log: %s", logfile);
            free(logfile);
            return;
        } else {
            wprintw(window, "Do nothing. Current pgbouncer not local.");
            free(logfile);
            return;
        }
    } else {
        fclose(conn_opts->log);
        conn_opts->log_opened = false;
        return;
    }
}

/*
 ******************************************************** routine function **
 * Print pgbouncer log.
 *
 * IN:
 * @window          Window where log will be printed.
 * @conn_opts       Current connection options.
 ****************************************************************************
 */
void print_log(WINDOW * window, struct conn_opts_struct * conn_opts)
{
    int x, y;
    int lines = 1;
    int pos = 2;
    int ch;
    unsigned long long int length, offset;
    char buffer[BUFFERSIZE];

    getbegyx(window, y, x);
    fseek(conn_opts->log, 0, SEEK_END);
    length = ftell(conn_opts->log);

    do {
        offset = length - pos;
        if (offset > 0) {
            fseek(conn_opts->log, offset, SEEK_SET);
            ch = fgetc(conn_opts->log);
            pos++;
            if (ch == '\n')
                lines++;
            } else 
                break;
    } while (lines != (LINES - y));

    fseek(conn_opts->log, (offset + 1), SEEK_SET);
    wclear(window);

    wmove(window, 1, 0);
    while (fgets(buffer, 1024, conn_opts->log) != NULL) {
        wprintw(window, "%s", buffer);
        wrefresh(window);
    }
    wresize(window, y, x);
}

/*
 ****************************************************** key press function **
 * Edit the current configuration settings.
 *
 * IN:
 * @window      Window where errors will be displayed.
 * @conn_opts   Connection options.
 * @conn        Current pgbouncer connection.
 *
 * RETURNS:
 * Open configuration file in $EDITOR.
 ****************************************************************************
 */
void edit_config(WINDOW * window, struct conn_opts_struct * conn_opts, PGconn * conn)
{
    char * conffile = (char *) malloc(sizeof(char) * 128);
    pid_t pid;

    if (check_pgb_listen_addr(conn_opts)) {
        get_conf_value(conn, PGB_CONFIG_CONFFILE, conffile);
        if (strlen(conffile) != 0) {
            pid = fork();                   /* start child */
            if (pid == 0) {
                char * editor = (char *) malloc(sizeof(char) * 128);
                if ((editor = getenv("EDITOR")) == NULL)
                    editor = DEFAULT_EDITOR;
                execlp(editor, editor, conffile, NULL);
                free(editor);
                exit(EXIT_FAILURE);
            } else if (pid < 0) {
                wprintw(window, "Can't open %s: fork failed.", conffile);
                return;
            } else if (waitpid(pid, NULL, 0) != pid) {
                wprintw(window, "Unknown error: waitpid failed.");
                return;
            }
        } else {
            wprintw(window, "Do nothing. Config file option not found.");
        }
    } else {
        wprintw(window, "Do nothing. Edit config not supported for remote pgbouncers.");
    }
    free(conffile);
    return;
}

/*
 ****************************************************** key press function **
 * Change refresh interval.
 *
 * IN:
 * @window              Window where prompt will be printed.
 * 
 * OUT:
 * @interval            Interval.
 ****************************************************************************
 */
float change_refresh(WINDOW * window, float interval)
{
    float interval_save = interval;
    char value[8];
    bool * with_esc = (bool *) malloc(sizeof(bool));
    char * str = (char *) malloc(sizeof(char) * 128);

    echo();
    cbreak();
    nodelay(window, FALSE);
    keypad(window, TRUE);

    wprintw(window, "Change refresh interval from %.1f to ", interval / 1000000);
    wrefresh(window);

    cmd_readline(window, 36, with_esc, str);
    strcpy(value, str);
    free(str);
    if (strlen(value) != 0 && *with_esc == false) {
        if (strlen(value) != 0) {
            interval = atof(value);
            if (interval < 0) {
                wprintw(window, "Should be positive value.");
                interval = interval_save;
            } else {
              interval = interval * 1000000;
            }
        }
    } else if (strlen(value) == 0 && *with_esc == false ) {
        interval = interval_save;
    }

    free(with_esc);
    noecho();
    cbreak();
    nodelay(window, TRUE);
    keypad(window, FALSE);
    return interval;
}

/*
 ****************************************************** key press function **
 * Print on-program help.
 ****************************************************************************
 */
void print_help_screen(void)
{
    WINDOW * w;
    int ch;

    w = subwin(stdscr, 0, 0, 0, 0);
    cbreak();
    nodelay(w, FALSE);
    keypad(w, TRUE);

    wclear(w);
    wprintw(w, "Help for interactive commands - %s version %.1f (%s)\n\n",
            PROGRAM_NAME, PROGRAM_VERSION, PROGRAM_RELEASE);
    wprintw(w, "   1..8       switch between consoles.\n \
  a,c,d,p,s     show: 'a' stats, 'c' clients, 's' servers, 'd' databases, 'p' pools.\n \
  K,M,P,R,S,Z   perform: 'K' kill, 'M' reload, 'P' pause, 'R' resume,\n \
                         'S' suspend, 'Z' shutdown.\n \
  N,Ctrl+D      'N' add new connection, Ctrl+D close current connection.\n\n \
  W         write connections info into ~/.pgbrc.\n \
  L         show log file (only for local pgbouncers).\n \
  C,E       'C' show config, 'E' edit config (edit only for local pgbouncers).\n \
  I,i       'I' set refresh interval, 'i' change color scheme.\n \
  h         show help screen.\n \
  q         quit.\n\n");
    wprintw(w, "Type 'Esc' to continue.\n");

    do {
        ch = wgetch(w);
    } while (ch != 27);

    cbreak();
    nodelay(w, TRUE);
    keypad(w, FALSE);
    delwin(w);
}

/*
 *********************************************************** init function **
 * Init output colors.
 *
 * IN:
 * @ws_color            Summary window current color.
 * @wc_color            Cmdline window current color.
 * @wa_color            Pgbouncer answer window current color.
 * @wl_color            Pgbouncer log file window current color.
 ****************************************************************************
 */
void init_colors(int * ws_color, int * wc_color, int * wa_color, int * wl_color)
{
    start_color();
    init_pair(0, COLOR_BLACK,   COLOR_BLACK);
    init_pair(1, COLOR_RED,     COLOR_BLACK);
    init_pair(2, COLOR_GREEN,   COLOR_BLACK);
    init_pair(3, COLOR_YELLOW,  COLOR_BLACK);
    init_pair(4, COLOR_BLUE,    COLOR_BLACK);
    init_pair(5, COLOR_MAGENTA, COLOR_BLACK);
    init_pair(6, COLOR_CYAN,    COLOR_BLACK);
    init_pair(7, COLOR_WHITE,   COLOR_BLACK);
    /* set defaults */
    *ws_color = 7;
    *wc_color = 7;
    *wa_color = 7;
    *wl_color = 7;
}

/************************************************** color-related function **
 * Draw help of color-change screen.
 *
 * IN:
 * @ws_color            Summary window current color.
 * @wc_color            Cmdline window current color.
 * @wa_color            Pgbouncer answer window current color.
 * @wl_color            Pgbouncer log file window current color.
 * @target              Short name of the area which color will be changed.
 * @target_color        Next color of the area.
 ****************************************************************************
 */
void draw_color_help(WINDOW * w, int * ws_color, int * wc_color, int * wa_color, int * wl_color, int target, int * target_color)
{
        wclear(w);
        wprintw(w, "Help for color mapping - %s, version %.1f (%s)\n\n",
                PROGRAM_NAME, PROGRAM_VERSION, PROGRAM_RELEASE);
        wattron(w, COLOR_PAIR(*ws_color));
        wprintw(w, "\tpgbconsole: 2015-05-15 19:28:48, load average: 1.09, 1.13, 1.18\n\
\t      %%cpu: 12.5 us,  2.0 sy,  0.0 ni, 95.4 id,  0.1 wa,  0.0 hi,  0.\n\
\t console 1: 127.0.0.1:6432 postgres@pgbouncer    connection state: ok\n\
\t pgbouncer: pools: 3     databases: 3     clients: 55    servers: 9\n");
        wattroff(w, COLOR_PAIR(*ws_color));

        wattron(w, COLOR_PAIR(*wc_color));
        wprintw(w, "\tNasty message or input prompt.\n");
        wattroff(w, COLOR_PAIR(*wc_color));

        wattron(w, COLOR_PAIR(*wa_color));
        wattron(w, A_BOLD);
        wprintw(w, "\ttype   user       database    state    addr        port    local_addr\n");
        wattroff(w, A_BOLD);
        wprintw(w, "\tC      postgres   pgbouncer   active   127.0.0.1   57139   127.0.0.1\n\
\tC      pgbadmin   pgbouncer   active   127.0.0.1   57140   127.0.0.1\n\n");
        wattroff(w, COLOR_PAIR(*wa_color));

        wattron(w, COLOR_PAIR(*wl_color));
        wprintw(w, "\t2015-05-15 19:27:30.753 4136 LOG Stats: 98 req/s, in 1583 b/s, out 19\n\
\t2015-05-15 19:28:30.701 4136 LOG Stats: 103 req/s, in 1600 b/s, out 18\n\n");
        wattroff(w, COLOR_PAIR(*wl_color));


        wprintw(w, "1) Select a target as an upper case letter, current target is  %c :\n\
\tS = Summary Data, M = Messages/Prompt, P = Pgbouncer Information, L = Pgbouncer Log\n", target);
        wprintw(w, "2) Select a color as a number, current color is  %i :\n\
\t0 = black,  1 = red,      2 = green,  3 = yellow,\n\
\t4 = blue,   5 = magenta,  6 = cyan,   7 = white\n", *target_color);
        wprintw(w, "3) Then use keys: 'Esc' to abort changes, 'Enter' to commit and end.\n");

        touchwin(w);
        wrefresh(w);
}

/*
 ****************************************************** key press function **
 * Change output colors.
 *
 * IN:
 * @ws_color            Summary window current color.
 * @wc_color            Cmdline window current color.
 * @wa_color            Pgbouncer answer window current color.
 * @wl_color            Pgbouncer log file window current color.
 ****************************************************************************
 */
void change_colors(int * ws_color, int * wc_color, int * wa_color, int * wl_color)
{
    WINDOW * w;
    int ch,
        target = 'S',
        * target_color = ws_color;
    int ws_save = *ws_color,
        wc_save = *wc_color,
        wa_save = *wa_color,
        wl_save = *wl_color;

    w = subwin(stdscr, 0, 0, 0, 0);
    echo();
    cbreak();
    nodelay(w, FALSE);
    keypad(w, TRUE);

    do {
        draw_color_help(w, ws_color, wc_color, wa_color, wl_color, target, target_color);
        ch = wgetch(w);
        switch (ch) {
            case 'S':
                target = 'S';
                target_color = ws_color;
                break;
            case 'M':
                target = 'M';
                target_color = wc_color;
                break;
            case 'P':
                target = 'P';
                target_color = wa_color;
                break;
            case 'L':
                target = 'L';
                target_color = wl_color;
                break;
            case '0': case '1': case '2': case '3':
            case '4': case '5': case '6': case '7':
                *target_color = ch - '0';
                break;
            default:
                break;
        }
    } while (ch != '\n' && ch != 27);

    /* if Esc entered, restore previous colors */
    if (ch == 27) {
        *ws_color = ws_save;
        *wc_color = wc_save;
        *wa_color = wa_save;
        *wl_color = wl_save;
    }

    noecho();
    cbreak();
    nodelay(w, TRUE);
    keypad(w, FALSE);
    delwin(w);
}

/*
 ****************************************************************************
 * Main entry for pgbconsole program.
 ****************************************************************************
 */
int main (int argc, char *argv[])
{
    WINDOW  *w_summary, *w_cmdline, *w_answer, *w_log;
    struct conn_opts_struct * conn_opts[MAX_CONSOLE];
    struct stats_cpu_struct * st_cpu[2];
    enum context query_context = pools;
    PGresult    * res;
    PGconn      * conns[8];
    float interval = 1000000;
    static int console_no = 1;
    static int console_index = 0;
    int ch;

    int * ws_color = (int *) malloc(sizeof(int)),
        * wc_color = (int *) malloc(sizeof(int)),
        * wa_color = (int *) malloc(sizeof(int)),
        * wl_color = (int *) malloc(sizeof(int));

    /* Process args... */
    init_conn_opts(conn_opts);
    if ( argc > 1 ) {
        create_initial_conn(argc, argv, conn_opts);
        create_pgbrc_conn(argc, argv, conn_opts, 1);
    } else
        if (create_pgbrc_conn(argc, argv, conn_opts, 0) == PGBRC_READ_ERR)
            create_initial_conn(argc, argv, conn_opts);

    /* CPU stats related actions */
    init_stats(st_cpu);
    get_HZ();

    /* open connections to pgbouncers */
    prepare_conninfo(conn_opts);
    open_connections(conn_opts, conns);

    /* init ncurses windows */
    initscr();
    cbreak();
    noecho();
    nodelay(stdscr, TRUE);

    w_summary = newwin(5, 0, 0, 0);
    w_cmdline = newwin(1, 0, 4, 0);
    w_answer = newwin(0, 0, 5, 0);

    init_colors(ws_color, wc_color, wa_color, wl_color);

    /* main loop */
    while (1) {
        if (key_is_pressed()) {
            wattron(w_cmdline, COLOR_PAIR(*wc_color));
            ch = getch();
            switch (ch) {
                case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8':
                    console_index = switch_conn(w_cmdline, conn_opts, ch, console_index, console_no);
                    console_no = console_index + 1;
                    break;
                case 'N':
                    console_index = add_connection(w_cmdline, conn_opts, conns, console_index);
                    console_no = console_index + 1;
                    break;
                case 4:             // Ctrl + D 
                    console_index = close_connection(w_cmdline, conn_opts, conns, console_index);
                    console_no = console_index + 1;
                    break;
                case 'W':
                    write_pgbrc(w_cmdline, conn_opts);
                    break;
                case 'L':
                    log_process(w_cmdline, &w_log, conn_opts[console_index], conns[console_index]);
                    break;
                case 'M':
                    do_reload(w_cmdline, conns[console_index]);
                    break;
                case 'P':
                    do_pause(w_cmdline, conns[console_index]);
                    break;
                case 'R':
                    do_resume(w_cmdline, conns[console_index]);
                    break;
                case 'S':
                    do_suspend(w_cmdline, conns[console_index]);
                    break;
                case 'K':
                    do_kill(w_cmdline, conns[console_index]);
                    break;
                case 'Z':
                    do_shutdown(w_cmdline, conns[console_index]);
                    break;
                case 'p':
                    wprintw(w_cmdline, "Show pools");
                    query_context = pools;
                    break;
                case 'c':
                    wprintw(w_cmdline, "Show clients");
                    query_context = clients;
                    break;
                case 's':
                    wprintw(w_cmdline, "Show servers");
                    query_context = servers;
                    break;
                case 'd':
                    wprintw(w_cmdline, "Show databases");
                    query_context = databases;
                    break;
                case 'a':
                    wprintw(w_cmdline, "Show stats");
                    query_context = stats;
                    break;
                case 'C':
                    show_config(conns[console_index]);
                    break;
                case 'E':
                    edit_config(w_cmdline, conn_opts[console_index], conns[console_index]);
                    break;
                case 'I':
                    interval = change_refresh(w_cmdline, interval);
                    break;
                case 'i':
                    change_colors(ws_color, wc_color, wa_color, wl_color);
                    break;
                case 'h':
                    print_help_screen();
                    break;
                case 'q':
                    free(ws_color);
                    free(wa_color);
                    endwin();
                    close_connections(conn_opts, conns);
                    exit(EXIT_SUCCESS);
                    break;
                default:
                    wprintw(w_cmdline, "Unknown command - try 'h' for help.");
                    break;
            }
            wattroff(w_cmdline, COLOR_PAIR(*wc_color));
        } else {
            wattron(w_summary, COLOR_PAIR(*ws_color));
            wattron(w_answer, COLOR_PAIR(*wa_color));

            reconnect_if_failed(w_cmdline, conn_opts[console_index], conns[console_index]);
            wclear(w_summary);
            print_title(w_summary, argv[0]);
            print_loadavg(w_summary);
            print_cpu_usage(w_summary, st_cpu);
            print_conninfo(w_summary, conn_opts[console_index], conns[console_index], console_no);
            print_pgbouncer_summary(w_summary, conns[console_index]);
            wrefresh(w_summary);

            res = do_query(conns[console_index], query_context);
            print_data(w_answer, query_context, res);
            wrefresh(w_cmdline);
            wclear(w_cmdline);

            if (conn_opts[console_index]->log_opened) {
                wattron(w_log, COLOR_PAIR(*wl_color));
                print_log(w_log, conn_opts[console_index]);
                wattroff(w_log, COLOR_PAIR(*wl_color));
            }
            wattroff(w_summary, COLOR_PAIR(*ws_color));
            wattroff(w_answer, COLOR_PAIR(*wa_color));

            usleep(interval);
        }
    }
}

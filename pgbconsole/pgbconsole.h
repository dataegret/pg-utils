/*
 * pgbconsole: top-like console for Pgbouncer - PostgreSQL connection pooler.
 * (C) 2015 by Alexey V. Lesovsky (lesovsky <at> gmail.com)
 */

#define PROGRAM_NAME        "pgbconsole"
#define PROGRAM_VERSION     0.1
#define PROGRAM_RELEASE     "rc"
#define PROGRAM_AUTHORS_CONTACTS    "<lesovsky@gmail.com>"

#define _GNU_SOURCE

/* sizes and limits */
#define BUFFERSIZE 4096
#define MAX_CONSOLE 8

/* connectins defaults */
#define DEFAULT_HOST        "/tmp"
#define DEFAULT_PORT        "6432"
#define DEFAULT_USER        "postgres"
#define DEFAULT_DBNAME      "pgbouncer"

/* files */
#define STAT_FILE       "/proc/stat"
#define UPTIME_FILE     "/proc/uptime"
#define LOADAVG_FILE    "/proc/loadavg"
#define PGBRC_FILE      ".pgbrc"
#define PGBRC_READ_OK   0
#define PGBRC_READ_ERR  1
#define PAGER           "${PAGER:-less}"
#define DEFAULT_EDITOR  "vim"

/* misc */
#define PGB_CONFIG_LOGFILE  "logfile"
#define PGB_CONFIG_CONFFILE "conffile"
#define HZ              hz
unsigned int hz;

/* PostgreSQL answers */
#define PG_CMD_OK PGRES_COMMAND_OK
#define PG_TUP_OK PGRES_TUPLES_OK

/* Struct which define connection options */
struct conn_opts_struct
{
    int terminal;
    bool conn_used;
    char host[BUFFERSIZE];
    char port[BUFFERSIZE];
    char user[BUFFERSIZE];
    char dbname[BUFFERSIZE];
    char password[BUFFERSIZE];
    char conninfo[BUFFERSIZE];
    bool log_opened;
    FILE *log;
};

/* struct which used for cpu statistic */
struct stats_cpu_struct {
    unsigned long long cpu_user;
    unsigned long long cpu_nice;
    unsigned long long cpu_sys;
    unsigned long long cpu_idle;
    unsigned long long cpu_iowait;
    unsigned long long cpu_steal;
    unsigned long long cpu_hardirq;
    unsigned long long cpu_softirq;
    unsigned long long cpu_guest;
    unsigned long long cpu_guest_nice;
};

/* struct for column widths */
struct colAttrs {
    char name[20];
    int width;
};

#define CONN_OPTS_SIZE (sizeof(struct conn_opts_struct))
#define STATS_CPU_SIZE (sizeof(struct stats_cpu_struct))

/* enum for password purpose */
enum trivalue
{
    TRI_DEFAULT,
    TRI_NO,
    TRI_YES
};

/*
 * Macros used to display statistics values.
 * NB: Define SP_VALUE() to normalize to %;
 */
#define SP_VALUE(m,n,p) (((double) ((n) - (m))) / (p) * 100)

/* enum for query context */
enum context
{
    pools,
    clients,
    servers,
    databases,
    stats,
    config
};

/*
 *************************************************************************** 
 * Functions prototypes 
 ***************************************************************************
 */
/* routines */
struct colAttrs *
    calculate_width(struct colAttrs *columns, int row_count, int col_count, PGresult *res);
int
    key_is_pressed(void);
void
    shift_consoles(struct conn_opts_struct * conn_opts[], PGconn * conns[], int i);
double
    ll_sp_value(unsigned long long value1, unsigned long long value2, unsigned long long itv);
void
    clear_conn_opts(struct conn_opts_struct * conn_opt[], int i);
bool
    check_pgb_listen_addr(struct conn_opts_struct * conn_opts);
/* end routines */

/* startup functions */
void
    init_colors(int * ws_color, int * wc_color, int * wa_color, int * wl_color);
void
    init_conn_opts(struct conn_opts_struct *conn_opts[]);
void
    create_initial_conn(int argc, char *argv[], struct conn_opts_struct *conn_opts[]);
int
    create_pgbrc_conn(int argc, char *argv[], struct conn_opts_struct *conn_opts[], const int pos);
void
    prepare_conninfo(struct conn_opts_struct *conn_opts[]);
char * 
    password_prompt(const char *prompt, int maxlen, bool echo);
void
    open_connections(struct conn_opts_struct *conn_opts[], PGconn * conns[]);
/* End startup functions */

/* quit program functions */
void
    close_connections(struct conn_opts_struct *conn_opts[], PGconn * conns[]);
/* End quit program functions */

/* summary window functions */
void
    get_time(char * strtime);
void
    print_title(WINDOW * window, char * progname);
float
    get_loadavg();
void
    print_loadavg(WINDOW * window);
void
    print_conninfo(WINDOW * window, struct conn_opts_struct *conn_opts, PGconn *conn, int console_no);
void
    init_stats(struct stats_cpu_struct *st_cpu[]);
void
    read_cpu_stat(struct stats_cpu_struct *st_cpu, int nbr, 
                unsigned long long *uptime, unsigned long long *uptime0);
void
    write_cpu_stat_raw(WINDOW * window, struct stats_cpu_struct *st_cpu[],
                int curr, unsigned long long itv);
void
    print_cpu_usage(WINDOW * window, struct stats_cpu_struct *st_cpu[]);
unsigned long long
    get_interval(unsigned long long prev_uptime, unsigned long long curr_uptime);
void
    print_pgbouncer_summary(WINDOW * window, PGconn *conn);
/* End summary window functions */

/* cmd line window functions */
void
    cmd_readline(WINDOW * window, int pos, bool * with_esc, char * str);
void
    get_conf_value(PGconn * conn, char * config_option_name, char * config_option_value);
/* End cmd line window functions */

/* pgbouncer answer window functions */
void
    reconnect_if_failed(WINDOW * window, struct conn_opts_struct * conn_opts, PGconn * conn);
PGresult * 
    do_query(PGconn *conn, enum context query_context);
void
    print_data(WINDOW * window, enum context query_context, PGresult *res);
void
    print_log(WINDOW * window, struct conn_opts_struct * conn_opts);
/* End pgbouncer answer window functions */

/* Key press functions */
int
    add_connection(WINDOW * window, struct conn_opts_struct * conn_opts[],
            PGconn * conns[], int console_index);
int
    close_connection(WINDOW * window, struct conn_opts_struct * conn_opts[],
            PGconn * conns[], int console_index);
int
    switch_conn(WINDOW * window, struct conn_opts_struct * conn_opts[],
                int ch, int console_index, int console_no);
void
    write_pgbrc(WINDOW * window, struct conn_opts_struct * conn_opts[]);
void
    show_config(PGconn * conn);
void
    edit_config(WINDOW * window, struct conn_opts_struct * conn_opts, PGconn * conn);
float
    change_refresh(WINDOW * window, float interval);
void
    log_process(WINDOW * window, WINDOW ** w_log, struct conn_opts_struct * conn_opts, PGconn * conn);
void
    change_colors(int * ws_color, int * wc_color, int * wa_color, int * wl_color);
void
    draw_color_help(WINDOW * w, int * ws_color, int * wc_color, int * wa_color, int * wl_color, int target, int * target_color);
void
    print_usage(void);
void
    print_help_screen(void);
/* End key press functions */

/* Pgbouncer action function */
void do_reload(WINDOW * window, PGconn *conn);
void do_suspend(WINDOW * window, PGconn *conn);
void do_pause(WINDOW * window, PGconn *conn);
void do_resume(WINDOW * window, PGconn *conn);
void do_kill(WINDOW * window, PGconn *conn);
void do_shutdown(WINDOW * window, PGconn *conn);
/* END Pgbouncer action functions */

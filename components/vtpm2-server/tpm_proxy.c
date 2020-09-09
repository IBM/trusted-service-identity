/********************************************************************************/
/*										*/
/*			     	TPM Proxy for Unix				*/
/*			     Written by Stefan Berger				*/
/*		       IBM Thomas J. Watson Research Center			*/
/*	      $Id: tpm_proxy.c 4768 2017-07-28 13:19:28Z kgoldman $ 		*/
/*										*/
/* (c) Copyright IBM Corporation 2006, 2010.					*/
/*										*/
/* All rights reserved.								*/
/* 										*/
/* Redistribution and use in source and binary forms, with or without		*/
/* modification, are permitted provided that the following conditions are	*/
/* met:										*/
/* 										*/
/* Redistributions of source code must retain the above copyright notice,	*/
/* this list of conditions and the following disclaimer.			*/
/* 										*/
/* Redistributions in binary form must reproduce the above copyright		*/
/* notice, this list of conditions and the following disclaimer in the		*/
/* documentation and/or other materials provided with the distribution.		*/
/* 										*/
/* Neither the names of the IBM Corporation nor the names of its		*/
/* contributors may be used to endorse or promote products derived from		*/
/* this software without specific prior written permission.			*/
/* 										*/
/* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS		*/
/* "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT		*/
/* LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR	*/
/* A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT		*/
/* HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,	*/
/* SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT		*/
/* LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,	*/
/* DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY	*/
/* THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT		*/
/* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE	*/
/* OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.		*/
/********************************************************************************/

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <sys/ioctl.h>
//#include "tpm_driver.h"
#include "tpm_proxy.h"


#define DEFAULT_PORT 6543	/* default TCPIP server port */
#define LOAD32(buffer,offset)         ( ntohl(*(uint32_t *)&buffer[offset]) )

void usage(const char * name)
{
    printf("Usage: %s [--port|-p <n>] [--nodaemon|-n] [--verbose|-v] [--log|-l]\n"
	   "          [--device|-d <device name>] [--persist] [--persisttpm]\n"
	   "\n"
	   "options can be one of the following:\n"
	   "--port <n>   : The port number the server is supposed to be running on.\n"
	   "\tDefault - 6543\n"
	   "\tTypically 2321 for TPM 2.0\n"
	   "--nodaemon   : Prevents the process from going into the background.\n"
	   "\tDefault - in background\n"
	   "--log <filename> : Log transactions into given file.\n"
	   "--verbose    : verbose mode\n"
	   "--device     : TPM device; default is /dev/tpm0\n"
	   "\tUse /dev/tpmrm0 for TPM 2.0 resource manager\n"
	   "--persist    : The TPM device and socket are held open until the program exits\n"
	   "--persisttpm : The TPM device is held open until the program exits\n"
	   "\tDefault - close both sides after every packet\n"
	   "\n"
	   "The device (e.g., /dev/tpm0) must be read/write by the user running the proxy\n",
	   name);
}

int detach(void);
int startup(short port, FILE * logfile, int, const char *);
void signal_handler(int signum);

int persist = FALSE;	/* FALSE, close TPM and socket after every packet */
int persisttpm = FALSE;	/* FALSE, close TPM after every packet */
FILE * logfile = NULL;

int main(int argc, char ** argv)
{
    /* default command line parameters */
    int daemon = TRUE;		/* TRUE, process in background */
    int verbose = FALSE;	/* FALSE, no verbose tracing */
    int port = DEFAULT_PORT;	/* server port */
    char * logfilename = NULL;	/* no logging */
    char * tpm_device = "/dev/tpm0";	

    int rc = 0;
    int i = 1;
	
    setvbuf(stdout, 0, _IONBF, 0);      /* output may be going through pipe */

    while ((i < argc) && (rc == 0)) {
	if (0 == strcmp("-h",argv[i])) {
	    usage(argv[0]);
	    rc = 1;
	}
	else if (0 == strcmp("--port",argv[i]) ||
		 0 == strcmp("-p", argv[i])) {
	    i++;
	    if (i < argc) {
		port = atoi(argv[i]);
		if (port < 0 || port > 0xffff) {
		    printf("Error, bad port specified: %d\n", port);
		    rc = 1;
		}
	    } else {
		usage(argv[0]);
		rc = 1;
	    }
	}
	else if (0 == strcmp("--nodaemon",argv[i]) ||
		 0 == strcmp("-n",argv[i])) {
	    daemon = FALSE;
	}
	else if (0 == strcmp("--verbose",argv[i]) ||
		 0 == strcmp("-v",argv[i])) {
	    verbose = TRUE;
	}
	else if (0 == strcmp("--log",argv[i]) ||
		 0 == strcmp("-l",argv[i])) {
	    i++;
	    if (i < argc) {
		logfilename = (char *)strdup(argv[i]);
	    } else {
		usage(argv[0]);
		rc = 1;
	    }
	}
	else if (0 == strcmp("--device",argv[i]) ||
		 0 == strcmp("-d",argv[i])) {
	    i++;
	    if (i < argc) {
		tpm_device = (char *)strdup(argv[i]);
	    } else {
		usage(argv[0]);
		rc = 1;
	    }
	}
	else if (0 == strcmp("--persist",argv[i])) {
	    persist = TRUE;
	}
	else if (0 == strcmp("--persisttpm",argv[i])) {
	    persisttpm = TRUE;
	}
	else {
	    printf("Error, illegal command line parameter: %s\n", argv[i]);
	    rc = 1;
	}
	i++;
    }
    /* if command line arguments are OK */
    if (rc == 0) {
	if (NULL != logfilename) {
	    logfile = fopen(logfilename,"w");
	    if (NULL != logfile) {
		setvbuf(logfile, 0, _IONBF, 0);      /* output may be going through pipe */
		printf("Logging transactions in %s\n", logfilename);
	    } else {
		printf("Could not open logfile %s\n", logfilename);
		rc = 1;
	    }
	}
    }
    if (rc == 0) {
	int res = 1;
	if (TRUE == daemon) {
	    printf("Will become a daemon.\n");
	    res = detach();
	}
	if ( 0 != res) {
	    signal(SIGKILL, signal_handler);
	    signal(SIGINT , signal_handler);
	    signal(SIGTERM, signal_handler);
	    signal(SIGQUIT, signal_handler);
	    signal(SIGABRT, signal_handler);
	}
    }	    
    if (rc == 0) {
	printf("Starting server on port = %d\n", port);
	rc = startup(port, logfile, verbose, tpm_device);
    }
    return rc;
}


void signal_handler(int signum)
{
    if (NULL != logfile) {
	fclose(logfile);
	logfile = NULL;
    }
    exit(0);
}


void logging (FILE * logfile, const char * prefix, const unsigned char * buffer, int len)
{
    if (NULL != logfile) {
	int i = 0;
	if (NULL != prefix) {
	    fwrite(prefix, 1, strlen(prefix), logfile);
	}
	fwrite("  ", 1, 2, logfile);
	while (i < len) {
	    char buf[100];
	    sprintf(buf,"%02x ",(unsigned char)buffer[i]);
	    fwrite(buf, 1, strlen(buf), logfile);
	    i++;
	    if (0 == (i & 15) && (i < len)) {
		fwrite("\n", 1, 1, logfile);
		memset(buf, 0x20, sizeof(buf));
		if (NULL != prefix) {
		    fwrite(buf, 1, strlen(prefix) + 2, logfile);
		}
	    }
	}
	fwrite("\n",1,1,logfile);
    }
}

int startup(short port, FILE * logfile, int verbose, const char *tpm_device)
{
    int 	rc = 0;
    int         irc = 0;
    char 	messageBuffer[4096];
    size_t 	messageLength;
    int 	server_sockfd = -1;
    int 	client_sockfd;
    struct sockaddr_in server_addr;
    /* command/response buffer */
    unsigned char buffer[4096]; 	/* 4096 is the Linux driver buffer size */
    int len = 0;
    int paramSize;
    int tpm_fd = 0;

    /* create a socket */
    if (rc == 0) {
	server_sockfd  = socket(AF_INET, 
				SOCK_STREAM, 
				0);
        if (server_sockfd == -1) {
	    messageLength = sprintf(messageBuffer,
				    "Error creating server socket() %d %s\n",
				    errno, strerror(errno));
	    if (NULL != logfile) {
		logging(logfile, messageBuffer, NULL, 0);
	    }
	    logging(stdout, messageBuffer, NULL, 0);
            rc = 1;
        }
    }
    if (rc == 0) {
	memset(&server_addr, 0x0, sizeof(server_addr));
	server_addr.sin_family              = AF_INET;
	server_addr.sin_port                = htons(port);
	server_addr.sin_addr.s_addr         = htonl(INADDR_ANY);
	int on = 1;
        /* Set SO_REUSEADDR before calling bind() for servers that bind to a fixed port number. */
	irc = setsockopt(server_sockfd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
        if (irc != 0) {
	    messageLength = sprintf(messageBuffer,
				    "Error, server setsockopt() %d %s\n",
				    errno, strerror(errno));
	    if (NULL != logfile) {
		logging(logfile, messageBuffer, NULL, 0);
	    }
	    logging(stdout, messageBuffer, NULL, 0);
            rc = 1;
        }
    }
    /* bind the (local) server port name to the socket */
    if (rc == 0) {
	irc = bind(server_sockfd,
		   (struct sockaddr *)&server_addr,
		   sizeof(server_addr));
        if (irc != 0) {
	    messageLength = sprintf(messageBuffer,
				    "Error, server bind() %d %s\n",
				    errno, strerror(errno));
	    if (NULL != logfile) {
		logging(logfile, messageBuffer, NULL, 0);
	    }
	    logging(stdout, messageBuffer, NULL, 0);
            rc = 1;
        }
    }
    /* listen on the server socket connection for an incoming command */
    if (rc == 0) {
	irc = listen(server_sockfd, 1);
	if (irc != 0) {
	    messageLength = sprintf(messageBuffer,
				    "Error, server listen() %d %s\n",
				    errno, strerror(errno));
	    if (NULL != logfile) {
		logging(logfile, messageBuffer, NULL, 0);
	    }
	    logging(stdout, messageBuffer, NULL, 0);
	    rc = 1;
	}
    }
    /* if persisting, open the socket and TPM once here */
    if (persist) {
	struct sockaddr_in cli_addr;
	socklen_t cli_len = sizeof(cli_addr);
	/* block until connection from client */
	if (rc == 0) {
	    client_sockfd = accept(server_sockfd,
				   (struct sockaddr *)&cli_addr,
				   &cli_len);
	    if (client_sockfd < 0) {
		messageLength = sprintf(messageBuffer,
					"Error, accept() %d %s\n",
					errno, strerror(errno));
		if (NULL != logfile) {
		    logging(logfile, messageBuffer, NULL, 0);
		}
		logging(stdout, messageBuffer, NULL, 0);
		rc = 1;
	    }
	}
    }
    /* if persisting, open the TPM once here */
    if ((persist) ||
	(persisttpm)) {
	/* open the HW TPM */
	if (rc == 0) {
	    tpm_fd = open(tpm_device,O_RDWR);
	    if (tpm_fd <= 0) {
		messageLength = sprintf(messageBuffer,
					"Error opening %s\n",tpm_device);
		if (NULL != logfile) {
		    logging(logfile, messageBuffer, NULL, 0);
		}
		logging(stdout, messageBuffer, NULL, 0);
		rc = 1;
	    }
	}
    }
    /* this is the inner command/response loop */
    while (rc == 0) {
	/* if not persisting, open the socket each time */
	if (!persist) {
	    struct sockaddr_in cli_addr;
	    socklen_t cli_len = sizeof(cli_addr);
	    /* block until connection from client */
	    if (rc == 0) {
		client_sockfd = accept(server_sockfd,
				       (struct sockaddr *)&cli_addr,
				       &cli_len);
		if (client_sockfd < 0) {
		    messageLength = sprintf(messageBuffer,
					    "Error, accept() %d %s\n",
					    errno, strerror(errno));
		    if (NULL != logfile) {
			logging(logfile, messageBuffer, NULL, 0);
		    }
		    logging(stdout, messageBuffer, NULL, 0);
		    rc = 1;
		}
	    }
	}
	/* if not persisting, open the TPM each time */
	if (!persist && !persisttpm) {
	    /* open the HW TPM */
	    if (rc == 0) {
		tpm_fd = open(tpm_device,O_RDWR);
		if (tpm_fd <= 0) {
		    messageLength = sprintf(messageBuffer,
					    "Error opening %s\n",tpm_device);
		    if (NULL != logfile) {
			logging(logfile, messageBuffer, NULL, 0);
		    }
		    logging(stdout, messageBuffer, NULL, 0);
		    rc = 1;
		}
	    }
	}
	if (rc == 0) {
	    /* read the TPM command from the client application */
	    len = read(client_sockfd, buffer, sizeof(buffer));
	    /* socket read error */
	    if (len <= 0) {
		messageLength = sprintf(messageBuffer,
					"Error, socket read() %d %s\n",
					errno, strerror(errno));
		if (NULL != logfile) {
		    logging(logfile, messageBuffer, NULL, 0);
		}
		logging(stdout, messageBuffer, NULL, 0);
		rc = 1;
	    }
	}
	if (rc == 0) {
	    fcntl(tpm_fd, O_RDONLY|O_NONBLOCK);
	    /* log the TPM request */
	    if (NULL != logfile) {
		logging(logfile," REQUEST:", buffer, len);
	    }
	    if (verbose) {
		logging(stdout," REQUEST:", buffer, len);
	    }
	    /* write the command to the TPM */
	    len = write(tpm_fd, buffer, len);
	    if (len < 0) {
		messageLength = sprintf(messageBuffer,
					"Error, TPM write() %d %s\n",
					errno, strerror(errno));
		if (NULL != logfile) {
		    logging(logfile, messageBuffer, NULL, 0);
		}
		logging(stdout, messageBuffer, NULL, 0);
		rc = 1;
	    }
	}
	if (rc == 0) {
	    /* read the response from the TPM */
	    len = read(tpm_fd, buffer, sizeof(buffer));
	    if (len <= 0) {
		messageLength = sprintf(messageBuffer,
					"Error, TPM read() %d %s\n",
					errno, strerror(errno));
		if (NULL != logfile) {
		    logging(logfile, messageBuffer, NULL, 0);
		}
		logging(stdout, messageBuffer, NULL, 0);
		rc = 1;
	    }
	}
	if (rc == 0) {
	    /* log the TPM response */
	    if (NULL != logfile) {
		logging(logfile,"RESPONSE:", buffer, len);
	    }
	    if (verbose) {
		logging(stdout, "RESPONSE:", buffer, len);
	    }
	    /* get the response paramSize from the buffer at offset 2 */
	    paramSize = LOAD32(buffer, 2);
	    /* sanity check on response packet */
	    if (len != paramSize) {
		messageLength = sprintf(messageBuffer,
					"Error, Malformed TPM response, read %u paramSize %u\n",
					len, paramSize);
		if (NULL != logfile) {
		    logging(logfile, messageBuffer, NULL, 0);
		}
		logging(stdout, messageBuffer, NULL, 0);
		rc = 1;
	    }
	}
	if (rc == 0) {
	    /* This is likely obsolete.  There was a TPM at one time that returned something unusual
	       for the TPM_Quote command.  This work around ensures that the first byte is always
	       zero.  */
#if 0
	    buffer[0] = 0;
#endif
	}
	if (rc == 0) {
	    /* write the response to the socket client */
	    len = write(client_sockfd, buffer, len);
	    if (len <= 0) {
		messageLength = sprintf(messageBuffer,
					"Error, socket write() %d %s\n",
					errno, strerror(errno));
		if (NULL != logfile) {
		    logging(logfile, messageBuffer, NULL, 0);
		}
		logging(stdout, messageBuffer, NULL, 0);
		rc = 1;
	    }
	}
	/* if not persisting, close the socket each time */
	if (!persist) {
	    close(client_sockfd);
	}
	/* if not persisting, close the TPM each time */
	if (!persist && !persisttpm) {
	    /* close the TPM */
	    close(tpm_fd);
	}
    }
    /* if persisting, close the socket and TPM once at exit */
    if (persist) {
	close(client_sockfd);
    }
    if (persist || persisttpm) {
	close(tpm_fd);
    }
    close(server_sockfd);
    return rc;
}

int detach(void)
{
    signal(SIGHUP , SIG_IGN);
    if (getppid() != 1) {
	int childpid;
	signal(SIGTTOU, SIG_IGN);
	signal(SIGTTIN, SIG_IGN);
	signal(SIGTSTP, SIG_IGN);
	if ( (childpid = fork()) > 0) {
	    return 0;
	}
	setsid();
    }
    close(0);
    //	close(1);
    //	close(2);
    umask(0);
    chdir("/");
    return 1;
}

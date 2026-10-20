/* SPDX-License-Identifier: GPL-2.0-or-later. Header-only native IPC client. */
#ifndef CE_CLIENT_H
#define CE_CLIENT_H
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>
#define CE_SOCKET_PATH "/var/run/smcfan-ce.sock"
static inline int ce_request_at(const char *path, const char *request,
                                char *reply, size_t capacity) {
  if (!path || !request || !reply || capacity < 2 ||
      strlen(path) >= sizeof(((struct sockaddr_un *)0)->sun_path))
    return -1;
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0)
    return -1;
  struct timeval timeout = {0, 200000};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
#ifdef SO_NOSIGPIPE
  int yes = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
#endif
  struct sockaddr_un address;
  memset(&address, 0, sizeof address);
  address.sun_family = AF_UNIX;
  strcpy(address.sun_path, path);
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    close(fd);
    return -1;
  }
  if (connect(fd, (struct sockaddr *)&address, sizeof address)) {
    if (errno != EINPROGRESS) {
      close(fd);
      return -1;
    }
    struct pollfd event = {fd, POLLOUT, 0};
    int error = 0;
    socklen_t size = sizeof error;
    if (poll(&event, 1, 200) <= 0 ||
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) || error) {
      close(fd);
      return -1;
    }
  }
  if (fcntl(fd, F_SETFL, flags) < 0) {
    close(fd);
    return -1;
  }
  size_t n = strlen(request), sent = 0;
  while (sent < n) {
#ifdef MSG_NOSIGNAL
    ssize_t k = send(fd, request + sent, n - sent, MSG_NOSIGNAL);
#else
    ssize_t k = send(fd, request + sent, n - sent, 0);
#endif
    if (k <= 0) {
      close(fd);
      return -1;
    }
    sent += (size_t)k;
  }
  shutdown(fd, SHUT_WR);
  size_t used = 0;
  int complete = 0;
  while (used < capacity - 1) {
    ssize_t k = recv(fd, reply + used, capacity - 1 - used, 0);
    if (k == 0) {
      complete = 1;
      break;
    }
    if (k < 0) {
      close(fd);
      return -1;
    }
    used += (size_t)k;
  }
  reply[used] = 0;
  close(fd);
  return complete && used ? 0 : -1;
}
static inline int ce_request(const char *request, char *reply,
                             size_t capacity) {
  return ce_request_at(CE_SOCKET_PATH, request, reply, capacity);
}
#endif

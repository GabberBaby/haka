/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#include <signal.h>
#include <time.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <sys/syscall.h>

#include <haka/timer.h>
#include <haka/error.h>
#include <haka/thread.h>
#include <haka/log.h>
#include <haka/compiler.h>


struct timer {
	timer_t         id;
	bool            armed;
	timer_callback  callback;
	void           *data;
};

static void timer_handler(int sig, siginfo_t *si, void *uc)
{
	struct timer *timer = (struct timer *)si->si_value.sival_ptr;

	if (timer) {
		timer->callback(timer_getoverrun(timer->id), timer->data);
	}
}

INIT static void _timer_init()
{
	struct sigaction sa;

	sa.sa_flags = SA_SIGINFO;
	sa.sa_sigaction = timer_handler;
	sigemptyset(&sa.sa_mask);
	if (sigaction(SIGALRM, &sa, NULL) == -1) {
		messagef(HAKA_LOG_FATAL, L"timer", L"%s", errno_error(errno));
		abort();
	}

	timer_init_thread();
}

bool timer_init_thread()
{
	return timer_unguard();
}

struct timer *timer_init(timer_callback callback, void *user)
{
	struct sigevent sev;

	struct timer *timer = malloc(sizeof(struct timer));
	if (!timer) {
		error(L"memory error");
		return NULL;
	}

	timer->armed = false;
	timer->callback = callback;
	timer->data = user;

	memset(&sev, 0, sizeof(sev));
	sev.sigev_notify = SIGEV_THREAD_ID;
	sev.sigev_signo = SIGALRM;
	sev.sigev_value.sival_ptr = timer;
	sev._sigev_un._tid = syscall(SYS_gettid);

	if (timer_create(CLOCK_MONOTONIC, &sev, &timer->id)) {
		free(timer);
		error(L"timer creation error: %s", errno_error(errno));
		return NULL;
	}

	return timer;
}

void timer_destroy(struct timer *timer)
{
	timer_delete(timer->id);
	free(timer);
}

bool timer_once(struct timer *timer, struct time *delay)
{
	struct itimerspec ts;
	memset(&ts, 0, sizeof(ts));

	ts.it_value.tv_sec = delay->secs;
	ts.it_value.tv_nsec = delay->nsecs;

	if (timer_settime(timer->id, 0, &ts, NULL)) {
		error(L"%s", errno_error(errno));
		return false;
	}
	return true;
}

bool timer_repeat(struct timer *timer, struct time *delay)
{
	struct itimerspec ts;

	ts.it_value.tv_sec = delay->secs;
	ts.it_value.tv_nsec = delay->nsecs;
	ts.it_interval = ts.it_value;

	if (timer_settime(timer->id, 0, &ts, NULL)) {
		error(L"%s", errno_error(errno));
		return false;
	}
	return true;
}

bool timer_stop(struct timer *timer)
{
	struct itimerspec ts;
	memset(&ts, 0, sizeof(ts));

	if (timer_settime(timer->id, 0, &ts, NULL)) {
		error(L"%s", errno_error(errno));
		return false;
	}
	return true;
}

bool timer_guard()
{
	sigset_t mask;

	sigemptyset(&mask);
	sigaddset(&mask, SIGALRM);
	if (!thread_sigmask(SIG_BLOCK, &mask, NULL)) {
		return false;
	}

	return true;
}

bool timer_unguard()
{
	sigset_t mask;

	sigemptyset(&mask);
	sigaddset(&mask, SIGALRM);
	if (!thread_sigmask(SIG_UNBLOCK, &mask, NULL)) {
		return false;
	}

	return true;
}
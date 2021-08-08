---
title: Python3源码阅读-Python中的锁
tags:
- Python
- Python源码
- 锁
---

1. Python的线程是从os申请的线程，比如说使用封装好的`pthread`。
2. 所有线程都持有唯一的

## 问题：

核心有两个问题没有明白

1. 解释器执行的时候究竟在哪个线程上执行的。
2. GIL是什么时候调用的。
3. 上下文如何切换。

线程的一个入口结构

```cpp
// Thread(target=func, args=(), kwargs={})
struct bootstate {
    PyInterpreterState *interp;  // 解释器的state
    PyObject *func; 
    PyObject *args;
    PyObject *keyw;
    PyThreadState *tstate; // 线程state
};
```


GIL的runtime锁结构：
```cpp
struct _gil_runtime_state {
    /* microseconds (the Python API uses seconds, though) */
    /* 一个线程用于 GIL的间隔 */
    unsigned long interval;
    /*最后一个持有GIL的PyThreadState(线程)，这有助于我们知道在丢弃GIL后是否还有其他线程被调度 */
    _Py_atomic_address last_holder;
    /* Whether the GIL is already taken (-1 if uninitialized). This is
       atomic because it can be read without any lock taken in ceval.c. */
   /* GIL是否被获取，这个是原子性的，因为在ceval.c中不需要任何锁就能够读取它 */
    _Py_atomic_int locked;
    /* Number of GIL switches since the beginning. */
   /* 从GIL创建之后，总共切换的次数 */
    unsigned long switch_number;
    /* This condition variable allows one or several threads to wait
       until the GIL is released. In addition, the mutex also protects
       the above variables. */
    /* cond允许一个或多个线程等待，直到GIL被释放 */
    PyCOND_T cond;
    /* 保护之前的mutex */
    PyMUTEX_T mutex;
#ifdef FORCE_SWITCHING
    /* This condition variable helps the GIL-releasing thread wait for
       a GIL-awaiting thread to be scheduled and take the GIL. */
    PyCOND_T switch_cond;
    PyMUTEX_T switch_mutex;
#endif
};
```

解释器的状态结构

```cpp
struct _ceval_runtime_state {
    /*递归限制，防止过度递归*/
    int recursion_limit;
    /* Records whether tracing is on for any thread.  Counts the number
       of threads for which tstate->c_tracefunc is non-NULL, so if the
       value is 0, we know we don't have to check this thread's
       c_tracefunc.  This speeds up the if statement in
       PyEval_EvalFrameEx() after fast_next_opcode. */
    /*是否追踪线程*/
    int tracing_possible;
    /* This single variable consolidates all requests to break out of
       the fast path in the eval loop. */
    _Py_atomic_int eval_breaker;
    /* Request for dropping the GIL */
    _Py_atomic_int gil_drop_request;  // 放弃GIL的请求
    struct _pending_calls pending;
    struct _gil_runtime_state gil;  // GIL的State结构体
};
```


```cpp
// Module/_threadmodule.c
// 创建线程
static void
t_bootstrap(void *boot_raw)
{
    struct bootstate *boot = (struct bootstate *) boot_raw;
    PyThreadState *tstate;
    PyObject *res;

    tstate = boot->tstate;
    tstate->thread_id = PyThread_get_thread_ident();
    _PyThreadState_Init(tstate);
    PyEval_AcquireThread(tstate); // 抢GIL，如果没抢到就挂起来。
    tstate->interp->num_threads++; // interp 记录
    res = PyObject_Call(boot->func, boot->args, boot->keyw); // 调用函数
    if (res == NULL) {
        if (PyErr_ExceptionMatches(PyExc_SystemExit))
            PyErr_Clear();
        else {
            PyObject *file;
            PyObject *exc, *value, *tb;
            PySys_WriteStderr(
                "Unhandled exception in thread started by ");
            PyErr_Fetch(&exc, &value, &tb);
            file = _PySys_GetObjectId(&PyId_stderr);
            if (file != NULL && file != Py_None)
                PyFile_WriteObject(boot->func, file, 0);
            else
                PyObject_Print(boot->func, stderr, 0);
            PySys_WriteStderr("\n");
            PyErr_Restore(exc, value, tb);
            PyErr_PrintEx(0);
        }
    }
    else
        Py_DECREF(res);
    Py_DECREF(boot->func);
    Py_DECREF(boot->args);
    Py_XDECREF(boot->keyw);
    PyMem_DEL(boot_raw);
    tstate->interp->num_threads--;
    PyThreadState_Clear(tstate);
    PyThreadState_DeleteCurrent();
    PyThread_exit_thread();
}

static PyObject *
thread_PyThread_start_new_thread(PyObject *self, PyObject *fargs)
{
    PyObject *func, *args, *keyw = NULL;
    struct bootstate *boot;
    unsigned long ident;
    /* 一堆check */
    if (!PyArg_UnpackTuple(fargs, "start_new_thread", 2, 3,
                           &func, &args, &keyw))
        return NULL;
    if (!PyCallable_Check(func)) {
        PyErr_SetString(PyExc_TypeError,
                        "first arg must be callable");
        return NULL;
    }
    if (!PyTuple_Check(args)) {
        PyErr_SetString(PyExc_TypeError,
                        "2nd arg must be a tuple");
        return NULL;
    }
    if (keyw != NULL && !PyDict_Check(keyw)) {
        PyErr_SetString(PyExc_TypeError,
                        "optional 3rd arg must be a dictionary");
        return NULL;
    }
    // 初始化子线程参数
    boot = PyMem_NEW(struct bootstate, 1);  // 创建一个boot
    if (boot == NULL)
        return PyErr_NoMemory();
    boot->interp = PyThreadState_GET()->interp;
    boot->func = func;
    boot->args = args;
    boot->keyw = keyw;
    // 申请线程
    boot->tstate = _PyThreadState_Prealloc(boot->interp);  // 子线程状态
    if (boot->tstate == NULL) {
        PyMem_DEL(boot);
        return PyErr_NoMemory();
    }
    Py_INCREF(func);
    Py_INCREF(args);
    Py_XINCREF(keyw);
    // 初始化多线程环境
    /*
     1. 如果GIL存在，return
     2. 如果不存在就，就创建一个
     */
    PyEval_InitThreads(); /* Start the interpreter's thread-awareness */
    // 创建thread
    // 初始化跑的函数是t_bootstrap 参数是 boot
    ident = PyThread_start_new_thread(t_bootstrap, (void*) boot);
    if (ident == PYTHREAD_INVALID_THREAD_ID) {
        PyErr_SetString(ThreadError, "can't start new thread");
        Py_DECREF(func);
        Py_DECREF(args);
        Py_XDECREF(keyw);
        PyThreadState_Clear(boot->tstate);
        PyMem_DEL(boot);
        return NULL;
    }
    return PyLong_FromUnsignedLong(ident);
}
```

## GIL具体的函数

+ `gil_created`：检测gil是否created
+ `create_gil`：创建gil
+ `take_gil`：


```cpp

static void take_gil(PyThreadState *tstate)
{
    int err;
    if (tstate == NULL)
        Py_FatalError("take_gil: NULL tstate");

    err = errno;
    MUTEX_LOCK(_PyRuntime.ceval.gil.mutex);

    //判断gil是否被释放, 如果被释放, 那么直接跳转到_ready
    if (!_Py_atomic_load_relaxed(&_PyRuntime.ceval.gil.locked))
        goto _ready;

    // 循环等待GIL放锁
    while (_Py_atomic_load_relaxed(&_PyRuntime.ceval.gil.locked)) {
        int timed_out = 0;
        unsigned long saved_switchnum;

        saved_switchnum = _PyRuntime.ceval.gil.switch_number;
        COND_TIMED_WAIT(_PyRuntime.ceval.gil.cond, _PyRuntime.ceval.gil.mutex,
                        INTERVAL, timed_out);
        /* If we timed out and no switch occurred in the meantime, it is time
           to ask the GIL-holding thread to drop it. */
        if (timed_out &&
            _Py_atomic_load_relaxed(&_PyRuntime.ceval.gil.locked) &&
            _PyRuntime.ceval.gil.switch_number == saved_switchnum) {
            SET_GIL_DROP_REQUEST();
        }
    }
_ready:
#ifdef FORCE_SWITCHING
    /* This mutex must be taken before modifying
       _PyRuntime.ceval.gil.last_holder (see drop_gil()). */
    MUTEX_LOCK(_PyRuntime.ceval.gil.switch_mutex);
#endif
    /* We now hold the GIL */
    // 第一件事，上锁
    _Py_atomic_store_relaxed(&_PyRuntime.ceval.gil.locked, 1);
    _Py_ANNOTATE_RWLOCK_ACQUIRED(&_PyRuntime.ceval.gil.locked, /*is_write=*/1);

    if (tstate != (PyThreadState*)_Py_atomic_load_relaxed(
                    &_PyRuntime.ceval.gil.last_holder))
    {
        _Py_atomic_store_relaxed(&_PyRuntime.ceval.gil.last_holder,
                                 (uintptr_t)tstate);
        ++_PyRuntime.ceval.gil.switch_number;
    }

#ifdef FORCE_SWITCHING
    COND_SIGNAL(_PyRuntime.ceval.gil.switch_cond);
    MUTEX_UNLOCK(_PyRuntime.ceval.gil.switch_mutex);
#endif
    if (_Py_atomic_load_relaxed(&_PyRuntime.ceval.gil_drop_request)) {
        RESET_GIL_DROP_REQUEST();
    }
    if (tstate->async_exc != NULL) {
        _PyEval_SignalAsyncExc();
    }

    MUTEX_UNLOCK(_PyRuntime.ceval.gil.mutex);
    errno = err;
}
```


## 申请线程并与解释器绑定

```c
PyThreadState *
_PyThreadState_Prealloc(PyInterpreterState *interp)
{
    return new_threadstate(interp, 0);
}
```

```cpp

PyThreadState *
PyThreadState_New(PyInterpreterState *interp)
{
    return new_threadstate(interp, 1);
}


static PyThreadState *
new_threadstate(PyInterpreterState *interp, int init)
{
    // 
    PyThreadState *tstate = (PyThreadState *)PyMem_RawMalloc(sizeof(PyThreadState));

    if (_PyThreadState_GetFrame == NULL)
        _PyThreadState_GetFrame = threadstate_getframe;

    if (tstate != NULL) {
        tstate->interp = interp;

        tstate->frame = NULL;
        tstate->recursion_depth = 0;
        tstate->overflowed = 0;
        tstate->recursion_critical = 0;
        tstate->stackcheck_counter = 0;
        tstate->tracing = 0;
        tstate->use_tracing = 0;
        tstate->gilstate_counter = 0;
        tstate->async_exc = NULL;
        tstate->thread_id = PyThread_get_thread_ident();

        tstate->dict = NULL;

        tstate->curexc_type = NULL;
        tstate->curexc_value = NULL;
        tstate->curexc_traceback = NULL;

        tstate->exc_state.exc_type = NULL;
        tstate->exc_state.exc_value = NULL;
        tstate->exc_state.exc_traceback = NULL;
        tstate->exc_state.previous_item = NULL;
        tstate->exc_info = &tstate->exc_state;

        tstate->c_profilefunc = NULL;
        tstate->c_tracefunc = NULL;
        tstate->c_profileobj = NULL;
        tstate->c_traceobj = NULL;

        tstate->trash_delete_nesting = 0;
        tstate->trash_delete_later = NULL;
        tstate->on_delete = NULL;
        tstate->on_delete_data = NULL;

        tstate->coroutine_origin_tracking_depth = 0;

        tstate->coroutine_wrapper = NULL;
        tstate->in_coroutine_wrapper = 0;

        tstate->async_gen_firstiter = NULL;
        tstate->async_gen_finalizer = NULL;

        tstate->context = NULL;
        tstate->context_ver = 1;

        tstate->id = ++interp->tstate_next_unique_id;

        if (init)
            _PyThreadState_Init(tstate);

        HEAD_LOCK();
        tstate->prev = NULL;
        tstate->next = interp->tstate_head;
        if (tstate->next)
            tstate->next->prev = tstate;
        interp->tstate_head = tstate;
        HEAD_UNLOCK();
    }

    return tstate;
}
```


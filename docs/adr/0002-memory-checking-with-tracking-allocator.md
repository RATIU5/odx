# Memory checking uses Odin's tracking allocator, nothing else

The memory checker has one mechanism: `odx test` runs the stock test runner with `ODIN_TEST_FAIL_ON_BAD_MEMORY`, and `odx run` builds a generated wrapper that calls the user's `main` with a tracking allocator. We rejected ASan, clang and patching the runtime, because every odx command must need only the Odin compiler and never change user code. The cost is a documented list of what the memory checker can't see (the memory checker spec's Out of Scope).

package app

Handle :: int when ODIN_OS == .Windows else i32

path_limit :: 260 when ODIN_OS == .Windows else 4096

typed_handle: typeid : int when ODIN_OS == .Windows else i32

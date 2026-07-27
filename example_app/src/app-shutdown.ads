--  Process-level shutdown coordination for the server main. Installing this
--  package (withing it) attaches a handler for SIGTERM -- the graceful-stop
--  signal used by `kill`, docker stop, systemd and Kubernetes -- at
--  elaboration. The server main serves in a task and calls Await_Stop, so the
--  signal unblocks it and lets it stop the server and close persistence
--  cleanly instead of being killed mid-write. (SIGINT/Ctrl-C is left to the
--  GNAT runtime, which reserves it; use SIGTERM for a graceful stop.) The test
--  and CLI binaries do not with this package, so they install no handler.
package App.Shutdown is

   --  Block the calling task until SIGTERM has been delivered. Returns
   --  immediately if the signal already arrived.
   procedure Await_Stop;

end App.Shutdown;

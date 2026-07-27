with Database;

--  Database lifecycle and serialized access facade for example app persistence.
--
--  Concurrency model:
--    * In-process, every access goes through With_Database, which holds a
--      process-wide gate -- handlers, the websocket path and startup/shutdown
--      never touch the handle concurrently.
--    * Across processes, the storage engine takes an OS file lock, so a second
--      process opening the same carrier is refused. Open_If_Needed treats that
--      as transient and retries with a short backoff; only if it never clears
--      (or the failure is not lock contention) does it raise Storage_Unavailable.
package App.Database is

   --  Raised when the carrier cannot be opened -- lock contention that did not
   --  clear within the retry budget, or a non-transient failure (corrupt file,
   --  I/O error). Distinct from Program_Error so callers can tell a storage
   --  outage from a logic fault; the message carries the engine status code.
   Storage_Unavailable : exception;

   --  Open/create and prepare storage.
   --  Initialize persistence storage.
   --  @return No return value.
   procedure Initialize;

   --  Execute DB work while holding a process-wide gate.
   --  Serialize access to the app database handle.
   --  @param Process Callback executed with the open database handle.
   --  @return No return value.
   procedure With_Database (Process : not null access procedure (DB : in out Standard.Database.Handle));

   --  Close database handle at application shutdown.
   --  Close persistence storage.
   --  @return No return value.
   procedure Close;
end App.Database;

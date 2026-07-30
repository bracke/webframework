--  Webframework_Logging — webframework's diagnostics logger, implemented over
--  the `logging` library. It offers a small process-global, string-message API
--  (the shape webframework's internals call), while the events, redaction, and
--  logfmt/JSON encoding all come from the logging crate and the stderr sink from
--  logging_runtime. webframework has no logging implementation of its own; this
--  bridge is its logger.
package Webframework_Logging is

   type Level_Type is (Debug_Level, Info_Level, Warn_Level, Error_Level);

   --  Set the minimum level emitted (process-global; thread-safe).
   procedure Set_Minimum_Level (Level : Level_Type);

   --  The configured minimum level.
   function Minimum_Level return Level_Type;

   --  Whether a message at Level would be emitted.
   function Enabled (Level : Level_Type) return Boolean;

   --  Select structured output: True => JSON, False => logfmt.
   procedure Set_Structured (Enabled : Boolean);

   --  Whether structured (JSON) output is selected.
   function Structured return Boolean;

   procedure Debug (Message : String);
   procedure Info  (Message : String);
   procedure Warn  (Message : String);
   procedure Error (Message : String);

end Webframework_Logging;

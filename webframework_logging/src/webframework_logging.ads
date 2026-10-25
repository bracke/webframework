--  Webframework_Logging -- webframework's small process-global diagnostics
--  logger. Messages are emitted to standard error as logfmt or JSON.
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

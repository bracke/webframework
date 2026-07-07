package Web.Logging is
   type Level_Type is (Debug_Level, Info_Level, Warn_Level, Error_Level);

   --  Set the minimum level emitted by logging helpers.
   --  @param Level Lowest log level to write.
   --  @return No return value.
   procedure Set_Minimum_Level (Level : Level_Type);

   --  Return the configured minimum log level.
   --  @return Current minimum log level.
   function Minimum_Level return Level_Type;

   --  Check whether a log level would be emitted.
   --  @param Level Log level to test.
   --  @return True when messages at this level are enabled.
   function Enabled (Level : Level_Type) return Boolean;

   --  Enable or disable key/value structured log output.
   --  @param Enabled True for key/value output; False for bracketed text output.
   --  @return No return value.
   procedure Set_Structured (Enabled : Boolean);

   --  Check whether key/value structured output is enabled.
   --  @return True when structured output is enabled.
   function Structured return Boolean;

   --  Log debug-level text.
   --  @param Message Message to log.
   --  @return No return value.
   procedure Debug (Message : String);

   --  Log info-level text.
   --  @param Message Message to log.
   --  @return No return value.
   procedure Info (Message : String);

   --  Log warning-level text.
   --  @param Message Message to log.
   --  @return No return value.
   procedure Warn (Message : String);

   --  Log error-level text.
   --  @param Message Message to log.
   --  @return No return value.
   procedure Error (Message : String);
end Web.Logging;

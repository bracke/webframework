package Web.Logging is
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

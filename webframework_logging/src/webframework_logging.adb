with Logging.Levels;
with Logging.Events;

with Logging_Runtime;
with Logging_Runtime.Clock;
with Logging_Runtime.Stderr_Sink;

package body Webframework_Logging is

   function To_Level (L : Level_Type) return Logging.Levels.Level is
     (case L is
         when Debug_Level => Logging.Levels.Debug,
         when Info_Level  => Logging.Levels.Info,
         when Warn_Level  => Logging.Levels.Warn,
         when Error_Level => Logging.Levels.Error);

   --  Process-global settings, guarded for concurrent access.
   protected Settings is
      procedure Set_Min (L : Level_Type);
      function Min return Level_Type;
      procedure Set_Struct (On : Boolean);
      function Struct return Boolean;
   private
      Cur_Min   : Level_Type := Debug_Level;
      Struct_On : Boolean := False;
   end Settings;

   protected body Settings is
      procedure Set_Min (L : Level_Type) is
      begin
         Cur_Min := L;
      end Set_Min;
      function Min return Level_Type is (Cur_Min);
      procedure Set_Struct (On : Boolean) is
      begin
         Struct_On := On;
      end Set_Struct;
      function Struct return Boolean is (Struct_On);
   end Settings;

   Clk : Logging_Runtime.Clock.System_Clock;
   Snk : Logging_Runtime.Stderr_Sink.Sink;

   procedure Put (L : Level_Type; Message : String) is
      Cap : constant Natural := Natural'Min (Message'Length, 4096) + 16;
      E   : Logging.Events.Event (Fields_Capacity => 0, Pool => Cap);
      Ok  : Boolean;
   begin
      if L < Settings.Min then
         return;
      end if;
      Logging.Events.Start (E, To_Level (L), Message);
      Logging.Events.Set_Time (E, Clk.Now);
      Logging.Events.Seal (E);
      Snk.Format :=
        (if Settings.Struct then Logging_Runtime.Json else Logging_Runtime.Logfmt);
      --  Diagnostics logging is best-effort: a failed write is contained by the
      --  sink and its result is intentionally not surfaced here.
      Logging_Runtime.Stderr_Sink.Emit (Snk, E, Ok);
   end Put;

   procedure Set_Minimum_Level (Level : Level_Type) is
   begin
      Settings.Set_Min (Level);
   end Set_Minimum_Level;

   function Minimum_Level return Level_Type is (Settings.Min);

   function Enabled (Level : Level_Type) return Boolean is
     (Level >= Settings.Min);

   procedure Set_Structured (Enabled : Boolean) is
   begin
      Settings.Set_Struct (Enabled);
   end Set_Structured;

   function Structured return Boolean is (Settings.Struct);

   procedure Debug (Message : String) is
   begin
      Put (Debug_Level, Message);
   end Debug;

   procedure Info (Message : String) is
   begin
      Put (Info_Level, Message);
   end Info;

   procedure Warn (Message : String) is
   begin
      Put (Warn_Level, Message);
   end Warn;

   procedure Error (Message : String) is
   begin
      Put (Error_Level, Message);
   end Error;

end Webframework_Logging;

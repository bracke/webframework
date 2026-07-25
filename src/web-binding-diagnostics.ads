with Ada.Strings.Bounded;
with Web.Binding.Errors;

--  Structured, redaction-safe binding diagnostics.
--
--  Emits events at the binding seams (codec selected, bind succeeded/failed,
--  limit exceeded, upload aborted, internal decoder exception, registry
--  construction failure) as structured records carrying ONLY safe fields: a
--  request correlation id, route id, codec id, error id, error count, source
--  kind, a redacted (rendered) path, and a limit category. No raw request data
--  ever appears -- no bodies, passwords, tokens, cookies, uploaded content or
--  secret field values (BIND-011). A sink observes events; the default sink is
--  a no-op, so diagnostics cost nothing until an application opts in.
package Web.Binding.Diagnostics is

   type Event_Kind is
     (Codec_Selected,
      Bind_Succeeded,
      Bind_Failed,
      Limit_Exceeded,
      Upload_Aborted,
      Internal_Exception,
      Registry_Failure);

   type Limit_Category is
     (No_Limit, Body_Size, Field_Size, Field_Count, Part_Count, Header_Size,
      Upload_Size, Depth, Token_Count, Item_Count);

   Max_Text : constant := 128;
   Max_Path : constant := 512;

   package Text_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Text);
   package Path_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Path);

   type Event is record
      Kind        : Event_Kind := Bind_Succeeded;
      Correlation : Text_Strings.Bounded_String;
      Route       : Text_Strings.Bounded_String;
      Codec       : Text_Strings.Bounded_String;
      Path        : Path_Strings.Bounded_String;
      Has_Source  : Boolean := False;
      Source      : Source_Kind := Structured_Body;
      Has_Error   : Boolean := False;
      Error       : Web.Binding.Errors.Error_Id :=
        Web.Binding.Errors.Internal_Decoder_Failure;
      Error_Count : Natural := 0;
      Limit       : Limit_Category := No_Limit;
   end record;

   --  A diagnostic sink. Applications implement it to receive events.
   type Sink is limited interface;

   --  Receive one event.
   --  @param S The sink.
   --  @param E The event.
   procedure Emit (S : in out Sink; E : Event) is abstract;

   --  Emit to a possibly-null sink (no-op when null).
   --  @param S The sink access (may be null).
   --  @param E The event.
   procedure Emit_To (S : access Sink'Class; E : Event);

   --  The limit category an error id implies, or No_Limit.
   --  @param Id The error id.
   --  @return The limit category.
   function Limit_Category_Of
     (Id : Web.Binding.Errors.Error_Id) return Limit_Category;

   --  Event builders.

   --  @param Correlation The request correlation id.
   --  @param Route The route id.
   --  @param Codec The selected codec id.
   --  @return A Codec_Selected event.
   function Codec_Selected_Event
     (Correlation : String; Route : String; Codec : String) return Event;

   --  @param Correlation The request correlation id.
   --  @param Route The route id.
   --  @return A Bind_Succeeded event.
   function Bind_Succeeded_Event
     (Correlation : String; Route : String) return Event;

   --  Build a Bind_Failed event from an error collection: the first error's id,
   --  redacted path and source, plus the total error count and limit category.
   --  @param Errors The bind errors.
   --  @param Correlation The request correlation id.
   --  @param Route The route id.
   --  @return A Bind_Failed event.
   function Bind_Failed_Event
     (Errors      : Web.Binding.Errors.Error_Collection;
      Correlation : String;
      Route       : String) return Event;

   --  @param Category The limit category exceeded.
   --  @param Correlation The request correlation id.
   --  @param Route The route id.
   --  @return A Limit_Exceeded event.
   function Limit_Event
     (Category : Limit_Category; Correlation : String; Route : String)
      return Event;

   --  @param Correlation The request correlation id.
   --  @param Route The route id.
   --  @return An Upload_Aborted event.
   function Upload_Aborted_Event
     (Correlation : String; Route : String) return Event;

   --  @param Correlation The request correlation id.
   --  @return A Registry_Failure event.
   function Registry_Failure_Event (Correlation : String) return Event;

private

   type Null_Sink is limited new Sink with null record;

   overriding procedure Emit (S : in out Null_Sink; E : Event) is null;

end Web.Binding.Diagnostics;

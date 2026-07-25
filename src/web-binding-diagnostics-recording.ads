--  In-memory recording sink: captures diagnostic events for inspection.
--
--  A bounded sink that stores the events it receives, for tests and for
--  applications that want to buffer and forward diagnostics.
package Web.Binding.Diagnostics.Recording is

   Max_Events : constant := 256;

   type Recorder is limited new Sink with private;

   overriding procedure Emit (S : in out Recorder; E : Event);

   --  The number of recorded events.
   --  @param S The recorder.
   --  @return The count.
   function Count (S : Recorder) return Natural;

   --  A recorded event by 1-based position.
   --  @param S The recorder.
   --  @param Index The position.
   --  @return The event.
   function Get (S : Recorder; Index : Positive) return Event;

   --  Discard all recorded events.
   --  @param S The recorder.
   procedure Clear (S : in out Recorder);

private

   type Event_Array is array (1 .. Max_Events) of Event;

   type Recorder is limited new Sink with record
      Used   : Natural := 0;
      Events : Event_Array;
   end record;

end Web.Binding.Diagnostics.Recording;

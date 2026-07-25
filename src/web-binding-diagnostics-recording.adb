package body Web.Binding.Diagnostics.Recording is

   overriding procedure Emit (S : in out Recorder; E : Event) is
   begin
      if S.Used < Max_Events then
         S.Used := S.Used + 1;
         S.Events (S.Used) := E;
      end if;
   end Emit;

   function Count (S : Recorder) return Natural is (S.Used);

   function Get (S : Recorder; Index : Positive) return Event is
     (S.Events (Index));

   procedure Clear (S : in out Recorder) is
   begin
      S.Used := 0;
   end Clear;

end Web.Binding.Diagnostics.Recording;

package body Web.Binding.Streams.Memory is

   use Ada.Strings.Unbounded;

   function Create
     (Data        : String;
      Chunk       : Positive := Positive'Last;
      Inject      : Fault_Kind := No_Fault;
      Fault_After : Natural := 0) return Memory_Stream is
   begin
      return S : Memory_Stream do
         S.Data := To_Unbounded_String (Data);
         S.Pos := 0;
         S.Chunk := Chunk;
         S.Inject := Inject;
         S.Fault_After := Fault_After;
      end return;
   end Create;

   overriding procedure Fetch
     (Stream  : in out Memory_Stream;
      Buffer  : out String;
      Last    : out Natural;
      Outcome : out Read_Outcome)
   is
      Total     : constant Natural := Length (Stream.Data);
      Remaining : constant Natural := Total - Stream.Pos;
   begin
      Last := Buffer'First - 1;

      --  Injected faults trigger once enough bytes have been delivered.
      if Stream.Inject /= No_Fault and then Stream.Pos >= Stream.Fault_After then
         Outcome := (if Stream.Inject = Premature_Eof then End_Of_Input
                     else Failed);
         return;
      end if;

      if Remaining = 0 then
         Outcome := End_Of_Input;
         return;
      end if;

      declare
         Take : constant Natural :=
           Natural'Min (Natural'Min (Remaining, Stream.Chunk), Buffer'Length);
      begin
         for I in 0 .. Take - 1 loop
            Buffer (Buffer'First + I) := Element (Stream.Data, Stream.Pos + I + 1);
         end loop;
         Stream.Pos := Stream.Pos + Take;
         Last := Buffer'First + Take - 1;
         Outcome := Chunk;
      end;
   end Fetch;

end Web.Binding.Streams.Memory;

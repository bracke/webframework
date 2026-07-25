with Ada.Strings.Unbounded;

--  In-memory input stream, also the test double.
--
--  Delivers a fixed byte string in chunks of a configurable size (down to one
--  byte, for chunk-boundary tests) and can inject a premature end of input or a
--  read failure after a given number of delivered bytes, so codecs can be tested
--  against fragmentation and transport faults deterministically.
package Web.Binding.Streams.Memory is

   type Fault_Kind is (No_Fault, Premature_Eof, Read_Failure, Cancel);

   type Memory_Stream is new Input_Stream with private;

   --  Create an in-memory stream.
   --  @param Data The bytes to deliver.
   --  @param Chunk Maximum bytes per Fetch (default: all at once).
   --  @param Inject A fault to raise after Fault_After bytes.
   --  @param Fault_After Bytes to deliver before the fault triggers.
   --  @return The stream.
   function Create
     (Data        : String;
      Chunk       : Positive := Positive'Last;
      Inject      : Fault_Kind := No_Fault;
      Fault_After : Natural := 0) return Memory_Stream;

   overriding procedure Fetch
     (Stream  : in out Memory_Stream;
      Buffer  : out String;
      Last    : out Natural;
      Outcome : out Read_Outcome);

private

   type Memory_Stream is new Input_Stream with record
      Data        : Ada.Strings.Unbounded.Unbounded_String;
      Pos         : Natural := 0;
      Chunk       : Positive := Positive'Last;
      Inject      : Fault_Kind := No_Fault;
      Fault_After : Natural := 0;
   end record;

end Web.Binding.Streams.Memory;

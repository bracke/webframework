--  Bounded input-stream abstraction for body codecs.
--
--  Body codecs read through this rather than the raw connection, so they work
--  identically over an in-memory buffer, a fragmented test feed, or (later) a
--  real streaming transport. Read enforces an aggregate byte limit and tracks
--  the byte offset; the outcome distinguishes a chunk, end of input, the limit
--  being exceeded, cancellation and a read failure -- none of which raise.
--
--  Concrete streams override Fetch (the backing pull); Read wraps it with the
--  limit accounting. Web.Binding.Streams.Memory is the in-memory and test
--  implementation (configurable chunking and injected faults).
package Web.Binding.Streams is

   type Read_Outcome is
     (Chunk,
      End_Of_Input,
      Over_Limit,
      Cancelled,
      Failed);

   type Input_Stream is abstract tagged limited record
      Consumed_Bytes : Byte_Count := 0;
      Limit          : Byte_Count := Byte_Count'Last;
   end record;

   --  Pull the next chunk from the backing into Buffer. Overridden per backing.
   --  @param Stream The stream.
   --  @param Buffer Receives bytes (up to Buffer'Length).
   --  @param Last The last written index (Buffer'First - 1 if none).
   --  @param Outcome Chunk, End_Of_Input, Cancelled or Failed.
   procedure Fetch
     (Stream  : in out Input_Stream;
      Buffer  : out String;
      Last    : out Natural;
      Outcome : out Read_Outcome) is abstract;

   --  Read the next chunk, enforcing the aggregate byte limit.
   --  @param Stream The stream (class-wide).
   --  @param Buffer Receives bytes.
   --  @param Last The last written index.
   --  @param Outcome The read outcome (Over_Limit if the limit is exceeded).
   procedure Read
     (Stream  : in out Input_Stream'Class;
      Buffer  : out String;
      Last    : out Natural;
      Outcome : out Read_Outcome);

   --  Total bytes read so far.
   --  @param Stream The stream.
   --  @return The byte offset.
   function Bytes_Read (Stream : Input_Stream'Class) return Byte_Count;

   --  Set the aggregate byte limit.
   --  @param Stream The stream.
   --  @param Limit The maximum total bytes.
   procedure Set_Limit (Stream : in out Input_Stream'Class; Limit : Byte_Count);

end Web.Binding.Streams;

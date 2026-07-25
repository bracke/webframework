package body Web.Binding.Streams is

   procedure Read
     (Stream  : in out Input_Stream'Class;
      Buffer  : out String;
      Last    : out Natural;
      Outcome : out Read_Outcome) is
   begin
      Fetch (Stream, Buffer, Last, Outcome);
      if Outcome = Chunk then
         Stream.Consumed_Bytes :=
           Stream.Consumed_Bytes + Byte_Count (Last - Buffer'First + 1);
         if Stream.Consumed_Bytes > Stream.Limit then
            Outcome := Over_Limit;
         end if;
      end if;
   end Read;

   function Bytes_Read (Stream : Input_Stream'Class) return Byte_Count is
   begin
      return Stream.Consumed_Bytes;
   end Bytes_Read;

   procedure Set_Limit
     (Stream : in out Input_Stream'Class; Limit : Byte_Count) is
   begin
      Stream.Limit := Limit;
   end Set_Limit;

end Web.Binding.Streams;

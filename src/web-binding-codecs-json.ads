with Ada.Strings.Unbounded;
with Web.Binding.Streams;
with Web.Binding.Errors;

--  Strict streaming JSON pull tokenizer.
--
--  Reads a JSON document from a body stream and yields one token at a time
--  (Start_Object, Key, String_Value, Number_Value, ..., End_Document), with no
--  DOM: the typed binding layer (phase 7) drives it directly. A one-character
--  lookahead over the stream means tokens and escapes may split across chunks
--  and the result is fragmentation-invariant; an explicit state stack (never
--  recursion) enforces structure and a bounded nesting depth. Strict by default:
--  rejects comments, trailing commas, trailing content, control characters in
--  strings, invalid escapes and surrogates, invalid UTF-8, and NaN/Infinity.
--  Bounds cap depth, token count, string length and numeric-literal length.
--  Malformed input yields an Error_Token, never an exception.
package Web.Binding.Codecs.JSON is

   type Token_Kind is
     (Start_Object,
      End_Object,
      Key,
      Start_Array,
      End_Array,
      String_Value,
      Number_Value,
      Boolean_Value,
      Null_Value,
      End_Document,
      Error_Token);

   type Config is record
      Max_Depth  : Depth_Count := 64;
      Max_Tokens : Token_Count := 100_000;
      Max_String : Byte_Count := 65_536;
      Max_Number : Byte_Count := 64;
   end record;

   Default_Config : constant Config := (others => <>);

   type Reader
     (Stream : access Web.Binding.Streams.Input_Stream'Class) is limited private;

   --  Prime the reader before the first Advance.
   --  @param R The reader.
   --  @param Settings The limits.
   procedure Start (R : in out Reader; Settings : Config := Default_Config);

   --  Advance to the next token. Idempotent once at End_Document or Error_Token.
   --  @param R The reader.
   procedure Advance (R : in out Reader);

   --  The current token kind.
   --  @param R The reader.
   --  @return The kind.
   function Kind (R : Reader) return Token_Kind;

   --  The token text: the decoded string for String_Value/Key, the raw literal
   --  for Number_Value; empty otherwise.
   --  @param R The reader.
   --  @return The text.
   function Text (R : Reader) return String;

   --  The boolean of a Boolean_Value token.
   --  @param R The reader.
   --  @return The boolean.
   function Bool_Value (R : Reader) return Boolean;

   --  The error id of an Error_Token.
   --  @param R The reader.
   --  @return The error id.
   function Error_Id (R : Reader) return Web.Binding.Errors.Error_Id;

   --  The 1-based line of the current token's start.
   --  @param R The reader.
   --  @return The line.
   function Line (R : Reader) return Line_Number;

   --  The 1-based column of the current token's start.
   --  @param R The reader.
   --  @return The column.
   function Column (R : Reader) return Column_Number;

   --  The 0-based byte offset of the current token's start.
   --  @param R The reader.
   --  @return The offset.
   function Offset (R : Reader) return Offset_Count;

private

   type Parse_State is
     (S_Doc_Value, S_Doc_Done,
      S_Value_Or_End, S_Value,
      S_Key_Or_End, S_Key, S_Colon, S_Comma_Or_End,
      S_Error, S_Done);

   type Frame is (In_Object, In_Array);
   type Frame_Stack is array (1 .. 4_096) of Frame;

   type Reader
     (Stream : access Web.Binding.Streams.Input_Stream'Class) is limited record
      Settings   : Config := Default_Config;
      --  Byte buffer and current-char lookahead.
      Buffer     : String (1 .. 4_096);
      Buf_Len    : Natural := 0;
      Buf_Pos    : Natural := 1;
      Stream_End : Boolean := False;
      Cur        : Character := ' ';
      Cur_Eof    : Boolean := False;
      Started    : Boolean := False;
      --  Position of Cur.
      At_Offset  : Offset_Count := 0;
      At_Line    : Line_Number := 1;
      At_Col     : Column_Number := 1;
      --  Structural state.
      State      : Parse_State := S_Doc_Value;
      Stack      : Frame_Stack;
      Depth      : Natural := 0;
      Tokens     : Token_Count := 0;
      --  Current token.
      Cur_Kind   : Token_Kind := End_Document;
      Cur_Text   : Ada.Strings.Unbounded.Unbounded_String;
      Cur_Bool   : Boolean := False;
      Cur_Err    : Web.Binding.Errors.Error_Id :=
        Web.Binding.Errors.Json_Malformed;
      Tok_Offset : Offset_Count := 0;
      Tok_Line   : Line_Number := 1;
      Tok_Col    : Column_Number := 1;
   end record;

end Web.Binding.Codecs.JSON;

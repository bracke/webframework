with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Binding.Errors;

package body Web.Binding.Codecs.URL_Encoded is

   function Hex_Value (C : Character) return Integer is
   begin
      case C is
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' => return 10 + Character'Pos (C) - Character'Pos ('a');
         when 'A' .. 'F' => return 10 + Character'Pos (C) - Character'Pos ('A');
         when others     => return -1;
      end case;
   end Hex_Value;

   procedure Parse
     (Stream   : in out Web.Binding.Streams.Input_Stream'Class;
      Result   : out Form_Source;
      Outcome  : out Parse_Outcome;
      Settings : Config := Default_Config)
   is
      use Web.Binding.Streams;

      Cap : constant Natural := Natural'Min (Settings.Max_Fields, Max_Stored_Fields);

      Name     : Unbounded_String;
      Value    : Unbounded_String;
      In_Value : Boolean := False;
      Started  : Boolean := False;
      Bad      : Boolean := False;
      Pct      : Natural := 0;   --  0 none, 1 seen '%', 2 seen '%' + one hex
      Pct_Hi   : Integer := 0;

      Fatal : Parse_Outcome := Parsed;
      Stop  : Boolean := False;

      procedure Emit (Ch : Character) is
      begin
         Started := True;
         if In_Value then
            if Length (Value) >= Settings.Max_Value then
               Fatal := Field_Too_Large;
               Stop := True;
               return;
            end if;
            Append (Value, Ch);
         else
            if Length (Name) >= Settings.Max_Name then
               Fatal := Field_Too_Large;
               Stop := True;
               return;
            end if;
            Append (Name, Ch);
         end if;
      end Emit;

      procedure Finalize_Pair is
      begin
         if not Started then
            return;
         end if;
         if Result.Length >= Cap then
            Fatal := Too_Many_Fields;
            Stop := True;
            return;
         end if;
         Result.Length := Result.Length + 1;
         Result.Pairs (Result.Length) := (Name, Value, Bad);
         Name := Null_Unbounded_String;
         Value := Null_Unbounded_String;
         In_Value := False;
         Started := False;
         Bad := False;
         Pct := 0;
      end Finalize_Pair;

      procedure Process (Ch : Character) is
      begin
         if Pct = 1 then
            declare
               H : constant Integer := Hex_Value (Ch);
            begin
               if H < 0 then
                  Bad := True;
                  Pct := 0;
                  Emit (Ch);
               else
                  Pct_Hi := H;
                  Pct := 2;
               end if;
            end;
         elsif Pct = 2 then
            declare
               H : constant Integer := Hex_Value (Ch);
            begin
               Pct := 0;
               if H < 0 then
                  Bad := True;
                  Emit (Ch);
               else
                  Emit (Character'Val (Pct_Hi * 16 + H));
               end if;
            end;
         else
            case Ch is
               when '%' =>
                  Pct := 1;
                  Started := True;
               when '+' =>
                  Emit ((if Settings.Plus_As_Space then ' ' else '+'));
               when '&' =>
                  Finalize_Pair;
               when '=' =>
                  if In_Value then
                     Emit ('=');
                  else
                     In_Value := True;
                     Started := True;
                  end if;
               when others =>
                  Emit (Ch);
            end case;
         end if;
      end Process;

      Buffer  : String (1 .. 4_096);
      Last    : Natural;
      Read_Out : Read_Outcome;
      Done    : Boolean := False;
   begin
      Result.Length := 0;

      while not Stop and then not Done loop
         Read (Stream, Buffer, Last, Read_Out);
         case Read_Out is
            when Chunk =>
               for I in Buffer'First .. Last loop
                  Process (Buffer (I));
                  exit when Stop;
               end loop;
            when End_Of_Input =>
               Done := True;
            when Over_Limit =>
               Fatal := Body_Too_Large;
               Stop := True;
            when Cancelled =>
               Fatal := Cancelled;
               Stop := True;
            when Failed =>
               Fatal := Stream_Failed;
               Stop := True;
         end case;
      end loop;

      --  Clean end of input: a dangling escape is malformed; flush the last pair.
      if Done and then not Stop then
         if Pct /= 0 then
            Bad := True;
         end if;
         Finalize_Pair;
      end if;

      Outcome := Fatal;
   end Parse;

   function Lookup
     (Source : Form_Source; Name : String)
      return Web.Binding.Sources.Occurrences
   is
      Result : Web.Binding.Sources.Occurrences := Web.Binding.Sources.Empty;
   begin
      for I in 1 .. Source.Length loop
         if To_String (Source.Pairs (I).Name) = Name then
            declare
               Loc : Web.Binding.Errors.Source_Location;
            begin
               Loc.Has_Ordinal := True;
               Loc.Ordinal := Parameter_Ordinal (I);
               Web.Binding.Sources.Add
                 (Result, To_String (Source.Pairs (I).Value), Loc,
                  Source.Pairs (I).Bad);
            end;
         end if;
      end loop;
      return Result;
   end Lookup;

   function Field_Count (Source : Form_Source) return Natural is
   begin
      return Source.Length;
   end Field_Count;

end Web.Binding.Codecs.URL_Encoded;

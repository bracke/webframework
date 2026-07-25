package body Web.Binding.Percent is

   --  The value of a hex digit, or -1 if not one.
   function Hex_Value (C : Character) return Integer is
   begin
      case C is
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' => return 10 + Character'Pos (C) - Character'Pos ('a');
         when 'A' .. 'F' => return 10 + Character'Pos (C) - Character'Pos ('A');
         when others     => return -1;
      end case;
   end Hex_Value;

   procedure Decode
     (Text          : String;
      Plus_As_Space : Boolean;
      Output        : out String;
      Last          : out Natural;
      Valid         : out Boolean)
   is
      Out_Idx : Natural := Output'First - 1;
      I       : Integer := Text'First;

      procedure Emit (C : Character) is
      begin
         Out_Idx := Out_Idx + 1;
         Output (Out_Idx) := C;
      end Emit;

   begin
      Valid := True;
      while I <= Text'Last loop
         declare
            C : constant Character := Text (I);
         begin
            if C = '%' then
               if I + 2 <= Text'Last
                 and then Hex_Value (Text (I + 1)) >= 0
                 and then Hex_Value (Text (I + 2)) >= 0
               then
                  Emit (Character'Val
                          (Hex_Value (Text (I + 1)) * 16
                           + Hex_Value (Text (I + 2))));
                  I := I + 3;
               else
                  --  Malformed escape: flag it and keep the '%' literally so
                  --  Last stays well-defined; the caller treats the value as bad.
                  Valid := False;
                  Emit ('%');
                  I := I + 1;
               end if;
            elsif C = '+' and then Plus_As_Space then
               Emit (' ');
               I := I + 1;
            else
               Emit (C);
               I := I + 1;
            end if;
         end;
      end loop;
      Last := Out_Idx;
   end Decode;

   function Decode
     (Text          : String;
      Plus_As_Space : Boolean;
      Valid         : out Boolean) return String
   is
      Buffer : String (1 .. Text'Length);
      Last   : Natural;
   begin
      Decode (Text, Plus_As_Space, Buffer, Last, Valid);
      return Buffer (1 .. Last);
   end Decode;

end Web.Binding.Percent;

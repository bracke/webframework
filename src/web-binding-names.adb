package body Web.Binding.Names is

   function Flat_Key
     (Style  : Nesting_Style;
      Prefix : String;
      Field  : String) return String is
   begin
      if Prefix = "" then
         return Field;
      end if;
      case Style is
         when Dotted      => return Prefix & "." & Field;
         when Bracketed   => return Prefix & "[" & Field & "]";
         when Underscored => return Prefix & "_" & Field;
      end case;
   end Flat_Key;

end Web.Binding.Names;

--  Flat-name adapters for nested fields on flat sources.
--
--  A flat source (query, URL-encoded form) has no nesting, so a nested field is
--  addressed by a composed key. The style is pluggable so an application can map
--  a nested path onto whatever convention its front end emits: user.name,
--  user[name] or user_name. The binding path stays properly nested regardless;
--  only the source lookup key is flattened.
package Web.Binding.Names is

   pragma Pure;

   type Nesting_Style is (Dotted, Bracketed, Underscored);

   --  The flat source key for a nested field under Prefix.
   --  Dotted -> "prefix.field"; Bracketed -> "prefix[field]"; Underscored ->
   --  "prefix_field".
   --  @param Style The naming convention.
   --  @param Prefix The parent key (may itself be composed).
   --  @param Field The nested field name.
   --  @return The composed flat key.
   function Flat_Key
     (Style  : Nesting_Style;
      Prefix : String;
      Field  : String) return String;

end Web.Binding.Names;

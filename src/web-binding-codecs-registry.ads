with Ada.Strings.Bounded;
with Web.Binding.Media_Types;

--  Immutable codec registry.
--
--  Codecs are registered against media-type patterns in a mutable Builder, then
--  Freeze validates the set and produces an immutable Registry (frozen before
--  concurrent serving, invariant BIND-012). Selection is deterministic with a
--  fixed precedence: an exact type/subtype match, then a structured-suffix match
--  (+json), then a wildcard (type/* then */*), then no match. Equal-specificity
--  ambiguity and invalid wildcards are startup errors reported by Freeze.
--
--  The registry maps a media type to a stable codec id; the application
--  dispatches the actual decoder on that id. Media-type sniffing is never
--  performed -- selection is by declared Content-Type only.
package Web.Binding.Codecs.Registry is

   Max_Codecs : constant := 64;
   Max_Id     : constant := 64;

   package Ids is new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Id);

   subtype Codec_Id is Ids.Bounded_String;

   --  Policy for an absent Content-Type.
   type Missing_Policy is (Reject_Missing, Allow_Empty_Body, Use_Default);

   type Builder is limited private;

   --  Reset a builder to empty.
   --  @param B The builder.
   procedure Reset (B : out Builder);

   --  Register a codec for an exact type/subtype (e.g. application/json).
   --  @param B The builder.
   --  @param Id The stable codec id.
   --  @param Main The type.
   --  @param Sub The subtype.
   procedure Register_Exact
     (B : in out Builder; Id : String; Main : String; Sub : String);

   --  Register a codec for a structured suffix (e.g. "json" -> */*+json).
   --  @param B The builder.
   --  @param Id The stable codec id.
   --  @param Suffix The suffix without '+'.
   procedure Register_Suffix (B : in out Builder; Id : String; Suffix : String);

   --  Register a codec for a wildcard type ("application" -> application/*,
   --  "*" -> */*).
   --  @param B The builder.
   --  @param Id The stable codec id.
   --  @param Main The type, or "*".
   procedure Register_Wildcard (B : in out Builder; Id : String; Main : String);

   --  Set the absent-Content-Type policy and its default codec.
   --  @param B The builder.
   --  @param Policy The policy.
   --  @param Default_Id The codec id used for Use_Default.
   procedure Set_Missing
     (B : in out Builder; Policy : Missing_Policy; Default_Id : String := "");

   type Registry is private;

   type Freeze_Status is
     (Frozen_Ok, Ambiguous_Patterns, Invalid_Wildcard, Too_Many_Codecs);

   --  Validate and freeze the builder into an immutable registry.
   --  @param B The builder.
   --  @param R The frozen registry (valid only when Status is Frozen_Ok).
   --  @param Status The validation result.
   procedure Freeze
     (B : Builder; R : out Registry; Status : out Freeze_Status);

   type Selection (Matched : Boolean := False) is record
      case Matched is
         when True =>
            Id : Codec_Id;
         when False =>
            null;
      end case;
   end record;

   --  Select the codec for a media type (deterministic precedence).
   --  @param R The frozen registry.
   --  @param M The parsed media type.
   --  @return The selected codec, or no match.
   function Select_Codec
     (R : Registry; M : Web.Binding.Media_Types.Media_Type) return Selection;

   --  The codec to use when Content-Type is absent (only under Use_Default).
   --  @param R The frozen registry.
   --  @return The default codec, or no match.
   function Missing_Selection (R : Registry) return Selection;

   --  The absent-Content-Type policy.
   --  @param R The frozen registry.
   --  @return The policy.
   function Missing (R : Registry) return Missing_Policy;

private

   type Kind_Type is (K_Exact, K_Suffix, K_Wildcard);

   type Reg_Entry is record
      Kind   : Kind_Type := K_Exact;
      Main   : Codec_Id;
      Sub    : Codec_Id;
      Suffix : Codec_Id;
      Id     : Codec_Id;
   end record;

   type Entry_Array is array (1 .. Max_Codecs) of Reg_Entry;

   type Store is record
      Count      : Natural := 0;
      Entries    : Entry_Array;
      Missing    : Missing_Policy := Reject_Missing;
      Default_Id : Codec_Id;
   end record;

   type Builder is limited record
      Data : Store;
   end record;

   type Registry is record
      Data : Store;
   end record;

end Web.Binding.Codecs.Registry;

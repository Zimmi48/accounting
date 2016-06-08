module Lib exposing (..)


import Date exposing (Date)
import Date.Format as Date
import Json.Decode as Decode exposing ((:=), Decoder)
import Json.Encode as Encode
import Positive exposing (Positive)


type alias Transaction =
  { object : String
  , value : Positive Float
  , date : Date
  }


encodeTransaction : Transaction -> Encode.Value
encodeTransaction { object , value , date } =
  Encode.object
    [ ("object", Encode.string object)
    , ("value", Encode.float <| Positive.toNum value)
    , ("date", Encode.string <| Date.formatISO8601 date)
    ]


decodeTransaction : Decoder Transaction
decodeTransaction =
  Decode.object3 Transaction
    ("object" := Decode.string)
    ("value" :=
       Decode.customDecoder
         Decode.float
         (Positive.fromNum >> Result.fromMaybe "")
    )
    ("date" := Decode.customDecoder Decode.string Date.fromString)


type alias Account =
  { name : String
  , value : Float
  }


encodeAccount : Account -> Encode.Value
encodeAccount { name , value } =
  Encode.object
    [ ("name", Encode.string name)
    , ("value", Encode.float value)
    ]


decodeAccount : Decoder Account
decodeAccount =
  Decode.object2 Account
    ("name" := Decode.string)
    ("value" := Decode.float)

module Lib exposing (..)


import Date exposing (Date)
import Date.Format as Date
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Decode exposing ((:=), Decoder)
import Json.Encode as Encode
import Positive exposing (Positive)


-- helpers for Models


type alias Transaction =
  { object : String
  , value : Positive Float
  , date : Date
  , accountId : String
  }


encodeTransaction : Transaction -> Encode.Value
encodeTransaction { object , value , date , accountId } =
  Encode.object
    [ ("object", Encode.string object)
    , ("value", Encode.float <| Positive.toNum value)
    , ("date", Encode.string <| Date.formatISO8601 date)
    , ("account", Encode.string accountId)
    ]


decodeTransaction : Decoder Transaction
decodeTransaction =
  Decode.object4 Transaction
    ("object" := Decode.string)
    ("value" :=
       Decode.customDecoder
         Decode.float
         (Positive.fromNum >> Result.fromMaybe "")
    )
    ("date" := Decode.customDecoder Decode.string Date.fromString)
    ("account" := Decode.string)


type alias Account =
  { name : String
  , value : Float
  , id : String
  }


encodeAccount : Account -> Encode.Value
encodeAccount { name , value } =
  Encode.object
    [ ("name", Encode.string name)
    , ("value", Encode.float value)
    ]


decodeAccount : Decoder Account
decodeAccount =
  Decode.object3 Account
    ("name" := Decode.string)
    ("value" := Decode.float)
    ("id" := Decode.string)


-- helpers for Views

inputGr : String -> String -> (String -> msg) -> List (Attribute msg) -> Html msg
inputGr inputName helper msg attrs =
  div
    [ class "form-group" ]
    [ label [ for inputName ] [ text helper ]
    , input
        ( [ name inputName 
          , onInput msg
          , class "form-control"
          ] ++ attrs
        ) []
    ]

module Lib exposing (..)


import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Decode exposing ((:=), Decoder)
import Positive exposing (Positive)


-- helpers for Models


type alias Transaction =
  { object : String
  , value : Positive Float
  , date : Date
  , accountId : String
  }


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


decodeAccount : Decoder Account
decodeAccount =
  Decode.object3 Account
    ("name" := Decode.string)
    ("value" := Decode.float)
    ("_id" := Decode.string)


-- helpers for Views

inputGr : String -> String -> (String -> msg) -> List (Attribute msg) -> Html msg
inputGr inputName helper updateInput attrs =
  div
    [ class "form-group" ]
    [ label [ for inputName ] [ text helper ]
    , input
        ( [ name inputName
          , onInput updateInput
          , class "form-control"
          ] ++ attrs
        ) []
    ]


accountSelector : List Account -> (String -> msg) -> List (String, Bool) -> Html msg
accountSelector accounts updateAccount addClasses =
  div
    [ classList ( [ ("form-group", True) ] ++ addClasses ) ]
    [ label [ for "account" ] [ text "Account" ]
    , text " "
    , select
        [ name "account"
        , required True
        , class "form-control"
        , on
            "change"
            (Decode.object1 updateAccount targetValue)
        ]
        (List.indexedMap
           (\i { name , id } ->
              option
              [ value id
              , selected (i == 0)
              ]
              [ text name ]
           )
           accounts
        )
    ]

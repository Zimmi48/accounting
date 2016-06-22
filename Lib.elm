module Lib exposing (..)


import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Json exposing ((:=), Decoder)


-- helpers for Models


type alias Transaction =
  { object : String
  , value : Float
  , date : Date
  , accountId : String
  }


decodeTransaction : Decoder Transaction
decodeTransaction =
  Json.object4 Transaction
    ("object" := Json.string)
    ("value" := Json.float)
    ("date" := Json.customDecoder Json.string Date.fromString)
    ("account" := Json.string)


type alias Account =
  { name : String
  , value : Float
  , id : String
  }


decodeAccount : Decoder Account
decodeAccount =
  Json.object3 Account
    ("name" := Json.string)
    ("value" := Json.float)
    ("_id" := Json.string)


type alias Contact =
  { name : String
  , email : String
  }


decodeContact : Decoder Contact
decodeContact =
  Json.object2 Contact
    ("name" := Json.string)
    ("email" := Json.string)


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
            (Json.object1 updateAccount targetValue)
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


viewForm : Bool -> msg -> String -> List (Html msg) -> Html msg
viewForm notready submitMsg submitText content =
  Html.form
    (if notready then [] else [ onSubmit submitMsg ])
    ( content ++
      [ button
          [ type' "submit"
          , classList
              [ ("btn", True)
              , ("btn-success", True)
              ]
          , disabled notready
          ]
          [ text submitText ]
      ]
    )
  

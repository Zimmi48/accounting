module Lib exposing (..)


import Dialog
import Html.App as App
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
  , id : String
  }


decodeContact : Decoder Contact
decodeContact =
  Json.object3 Contact
    ("name" := Json.string)
    ("email" := Json.string)
    ("_id" := Json.string)


-- helpers for Views

inputGr : String -> String -> (String -> msg) -> List (Attribute msg) -> Html msg
inputGr inputName helper updateInput attrs =
  div
    [ class "form-group" ]
    [ label [ for inputName ] [ text helper ]
    , text " "
    , input
        ( [ name inputName
          , onInput updateInput
          , class "form-control"
          ] ++ attrs
        ) []
    ]


selector
  : String
  -> String
  -> List { a | name : String, id : String }
  -> (String -> msg)
  -> List (String, Bool)
  -> Bool
  -> Html msg
selector selectName helper objects updateSelect addClasses isRequired =
  div
    [ classList ( [ ("form-group", True) ] ++ addClasses ) ]
    [ label [ for selectName ] [ text helper ]
    , text " "
    , select
        [ name selectName
        , required isRequired
        , class "form-control"
        , on
            "change"
            (Json.object1 updateSelect targetValue)
        ]
        (List.indexedMap
           (\i { name , id } ->
              option
              [ value id
              , selected (i == 0)
              ]
              [ text name ]
           )
           objects
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


successButton : String -> Maybe msg -> Html msg
successButton buttonText msg =
  button
    [ case msg of
        Just msg ->
          onClick msg

        Nothing ->
          disabled True
        
    , classList
        [ ("btn", True)
        , ("btn-success", True)
        ]
    ]
  [ text buttonText ]


viewDialog
  : String -> Maybe dialogModel -> msg -> (dialogMsg -> msg) -> (dialogModel -> Html dialogMsg) -> Html msg
viewDialog title model closeMsg forwardMsg view =
  Maybe.map
    (\model ->
       { closeMessage = Just closeMsg
       , header = Just (h4 [] [text title])
       , body = Just (App.map forwardMsg <| view model)
       , footer = Nothing
       }
    )
    model
  |> Dialog.view


module AddAccount exposing (Model, init, Msg, update, view)


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import String


type alias Model = String


init : Model
init = ""


type Msg
  = UpdateName String
  | Submit


update : Msg -> Model -> (Model, Maybe String)
update msg model =
  case msg of
    UpdateName s ->
      (String.left 50 s, Nothing)

    Submit ->
      (model, Just model)


view : Model -> Html Msg
view model =
  Html.form
    [ onSubmit Submit ]
    [ div
        [ class "form-group" ]
        [ label [ for "name" ] [ text "Name" ]
        , input
            [ name "name"
            , placeholder "Current account"
            , value model
            , onInput UpdateName
            , class "form-control"
            ] []
        ]
    , button
        [ type' "submit"
        , classList
            [ ("btn", True)
            , ("btn-success", True)
            ]
        , disabled (String.isEmpty model)
        ]
        [ text "Create account" ]
    ]

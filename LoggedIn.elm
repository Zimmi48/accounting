module LoggedIn exposing (Model, view)


import Html exposing (..)
import Html.Attributes exposing (..)
import Kinvey exposing (..)


type alias Model =
  { session : Maybe Session
  , transactions : List String
  }


view : Model -> Html msg
view model =
  div []
    [ text "Success!"
    ]


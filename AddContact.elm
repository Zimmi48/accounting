module AddContact exposing (Model, init, Msg, update, view)


import Html exposing (..)
import Html.Attributes exposing (..)
import Json.Encode as Json
import Lib exposing (..)
import String


type alias Model =
  { name : String
  , email : String
  }


init : Model
init = Model "" ""


type Msg
  = UpdateName String
  | UpdateEmail String
  | Submit


update : Msg -> Model -> (Model, Maybe Json.Value)
update msg model =
  case msg of
    UpdateName s ->
      ( { model |
          name = String.left 50 s
        }
      , Nothing
      )

    UpdateEmail s ->
      ( { model |
          email = String.left 50 s
        }
      , Nothing
      )

    Submit ->
      if notready model then
        (model, Nothing)

      else
        ( model
        , Json.object
            [ ("name", Json.string model.name)
            , ("email", Json.string model.email)
            ] |> Just
        )


notready : Model -> Bool
notready { name, email } =
  String.isEmpty name || String.isEmpty email


view : Model -> Html Msg
view model =
  viewForm
    (notready model)
    Submit
    "Add contact"
    [ inputGr "contactname" "Name" UpdateName
        [ placeholder "John Smith"
        , value model.name
        , required True
        ]
    , inputGr "contactemail" "Email" UpdateEmail
        [ placeholder "john.smith@nasa.gov"
        , value model.email
        , required True
        ]
    ]

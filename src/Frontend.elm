module Frontend exposing (..)

import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Dialog
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Input as Input
import Html
import Html.Attributes as Attr
import Html.Events exposing (..)
import Lamdera
import Types exposing (..)
import Url


type alias Model =
    FrontendModel


app =
    Lamdera.frontend
        { init = init
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = \m -> Sub.none
        , view = view
        }


init : Url.Url -> Nav.Key -> ( Model, Cmd FrontendMsg )
init url key =
    ( { showDialog = Nothing
      , key = key
      }
    , Cmd.none
    )


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            ( model, Cmd.none )

        NoOpFrontendMsg ->
            ( model, Cmd.none )

        ShowDialog dialog ->
            ( { model | showDialog = Just dialog }
            , Cmd.none
            )

        Submit ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

        Cancel ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

        UpdateName name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = name }) }
                    , Cmd.none
                    )

                Just (AddAccountDialog dialogModel) ->
                    ( { model | showDialog = Just (AddAccountDialog { dialogModel | name = name }) }
                    , Cmd.none
                    )

                Just (AddGroupDialog dialogModel) ->
                    ( { model | showDialog = Just (AddGroupDialog { dialogModel | name = name }) }
                    , Cmd.none
                    )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | description = name }) }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )


view : Model -> Browser.Document FrontendMsg
view model =
    let
        config title inputs =
            { closeMessage = Just Cancel
            , maskAttributes = []
            , containerAttributes =
                [ padding 20
                , Background.color (rgb 1 1 1)
                , Border.solid
                , Border.rounded 5
                , Border.width 1
                , width (px 400)
                , centerX
                , centerY
                ]
            , headerAttributes = [ padding 20 ]
            , bodyAttributes = []
            , footerAttributes = []
            , header = Just (text title)
            , body =
                Just
                    (column []
                        inputs
                    )
            , footer =
                Just
                    (row [ centerX, spacing 70, padding 20 ]
                        [ Input.button redButtonStyle
                            { label = text "Cancel"
                            , onPress = Just Cancel
                            }
                        , Input.button greenButtonStyle
                            { label = text "Submit"
                            , onPress = Just Submit
                            }
                        ]
                    )
            }

        dialogConfig =
            model.showDialog
                |> Maybe.map
                    (\dialog ->
                        case dialog of
                            AddPersonDialog dialogModel ->
                                config "Add Person" (addPersonInputs dialogModel)

                            AddAccountDialog dialogModel ->
                                config "Add Account" []

                            AddGroupDialog dialogModel ->
                                config "Add Group" []

                            AddSpendingDialog dialogModel ->
                                config "Add Spending" []
                    )
    in
    { title = "Accounting"
    , body =
        -- Elm UI body
        [ layout
            [ inFront (Dialog.view dialogConfig)
            ]
            (column [ width fill ]
                [ row [ centerX, spacing 70, padding 20 ]
                    [ Input.button greenButtonStyle
                        { label = text "Add Person"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddPersonDialog
                                        { name = "" }
                                    )
                                )
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Account"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddAccountDialog
                                        { name = ""
                                        , owner = ""
                                        , bank = ""
                                        }
                                    )
                                )
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Group"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddGroupDialog
                                        { name = ""
                                        , members = []
                                        }
                                    )
                                )
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Spending"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddSpendingDialog
                                        { description = ""
                                        , day = 1
                                        , month = 1
                                        , year = 1970
                                        , totalSpending = 0
                                        , sharedSpending = []
                                        , personalSpending = []
                                        , transactions = []
                                        }
                                    )
                                )
                        }
                    ]
                ]
            )
        ]
    }


buttonStyle =
    [ spaceEvenly
    , padding 10
    , Border.solid
    , Border.rounded 5
    , Border.width 1
    ]


greenButtonStyle =
    buttonStyle ++ [ Background.color (rgb255 173 255 47) ]


redButtonStyle =
    buttonStyle ++ [ Background.color (rgb 1 0.5 0.5) ]


addPersonInputs { name } =
    [ Input.text [ Input.focusedOnLoad ]
        { label = Input.labelLeft [] (text "Name")
        , placeholder = Nothing
        , onChange = UpdateName
        , text = name
        }
    ]

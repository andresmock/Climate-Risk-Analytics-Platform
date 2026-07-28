from ingestion import __version__


def test_version_is_a_non_empty_string():
    assert isinstance(__version__, str)
    assert __version__

import litert_lm


_original_constrained_decoding_config = getattr(
    litert_lm, "ConstrainedDecodingConfig", None
)


def _model_compatible_constrained_decoding_config(*args, **kwargs):
    if _original_constrained_decoding_config is None:
        return None
    config = _original_constrained_decoding_config(*args, **kwargs)
    return config if getattr(config, "provider", None) is not None else None


# LiteRT-LM serve enables Gemma FST constraints even for ordinary text chat.
if _original_constrained_decoding_config is not None:
    litert_lm.ConstrainedDecodingConfig = _model_compatible_constrained_decoding_config

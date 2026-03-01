function ensure_dir(d)
%ENSURE_DIR Create directory if it doesn't exist.
if ~isfolder(d)
    mkdir(d);
end
end
